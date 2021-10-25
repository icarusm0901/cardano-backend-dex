module Executor.Services.KafkaService
    ( KafkaService(..)
    , mkKafkaService
    ) where

import           Control.Exception   as C (bracket) 
import           Kafka.Consumer
import           RIO
import           Prelude (print)
import qualified Streamly.Prelude    as S
import           RIO.ByteString      as BS
import           Data.Aeson
import           RIO.ByteString.Lazy as LBS
import           GHC.Natural
import           RIO.List            as List

import Executor.Models.Settings
import Executor.Services.Processor
import Executor.Models.KafkaModel
import Executor.Utils

import ErgoDex.State
import ErgoDex.Amm.Orders

data KafkaService env = KafkaService
    { runKafka :: HasKafkaConsumerSettings env => RIO env ()
    }

mkKafkaService :: Processor -> KafkaService env
mkKafkaService p = KafkaService $ runKafka' p

runKafka' :: HasKafkaConsumerSettings env => Processor -> RIO env ()
runKafka' p = do
    settings <- view kafkaSettingsL
    mkKafka p settings

-------------------------------------------------------------------------------------

consumerProps :: KafkaConsumerSettings -> ConsumerProperties
consumerProps settings = brokersList (List.map BrokerAddress (getBrokerList settings))
             <> groupId (ConsumerGroupId $ getGroupId settings)
             <> noAutoCommit
             <> logLevel KafkaLogInfo

consumerSub :: KafkaConsumerSettings -> Subscription
consumerSub settings = topics (List.map TopicName (getTopicsList settings))
           <> offsetReset Earliest

mkKafka :: Processor -> KafkaConsumerSettings -> RIO env ()
mkKafka p settings = 
    liftIO $ do
    _   <- print "Running kafka stream..."
    C.bracket mkConsumer clConsumer runHandler
    where
      mkConsumer = newConsumer (consumerProps settings) (consumerSub settings)
      clConsumer (Left err) = return (Left err)
      clConsumer (Right kc) = maybe (Right ()) Left <$> closeConsumer kc
      runHandler (Left err) = print err >> pure ()
      runHandler (Right kc) = runF p settings kc

runF :: Processor -> KafkaConsumerSettings -> KafkaConsumer -> IO ()
runF p settings consumer = S.drain $ S.repeatM $ pollMessageF p settings consumer

pollMessageF :: Processor -> KafkaConsumerSettings -> KafkaConsumer -> IO ()
pollMessageF Processor{..} settings consumer = do
    msgs <- pollMessageBatch consumer (Timeout $ fromIntegral . naturalToInteger $ getPollRate settings) (BatchSize $ fromIntegral . naturalToInteger $ getBatchSize settings)
    _   <- print msgs
    let parsedMsgs = fmap parseMessage msgs & catMaybes
    traverse process parsedMsgs
    err <- commitAllOffsets OffsetCommit consumer
    print $ "Offsets: " <> maybe "Committed." show err

parseMessage :: Either e (ConsumerRecord k (Maybe BS.ByteString)) -> Maybe (Confirmed AnyOrder)
parseMessage x = case x of Right xv -> crValue xv >>= (\msg -> decodeTest msg)
                           _        -> Nothing

decodeTest :: BS.ByteString -> Maybe (Confirmed AnyOrder)
decodeTest testData =
    let msg          = (decode $ LBS.fromStrict testData) :: Maybe KafkaMsg
        KafkaMsg{..} = unsafeFromMaybe msg
        maybeSwap    = (decode $ LBS.fromStrict order) :: Maybe Swap
        maybeDeposit = (decode $ LBS.fromStrict order) :: Maybe Deposit
        maybeRedeem  = (decode $ LBS.fromStrict order) :: Maybe Redeem
    in 
      if (isJust maybeSwap)         then Just $ Confirmed txOut (AnyOrder anyOrderPoolId (SwapAction $ unsafeFromMaybe maybeSwap))
      else if (isJust maybeDeposit) then Just $ Confirmed txOut (AnyOrder anyOrderPoolId (DepositAction $ unsafeFromMaybe maybeDeposit))
      else if (isJust maybeRedeem)  then Just $ Confirmed txOut (AnyOrder anyOrderPoolId (RedeemAction $ unsafeFromMaybe maybeRedeem))
      else Nothing