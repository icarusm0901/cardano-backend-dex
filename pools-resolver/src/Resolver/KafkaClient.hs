module Resolver.KafkaClient (runKafka) where

import Control.Exception as C (bracket) 
import Kafka.Consumer
import RIO
import Prelude (print)
import qualified Streamly.Prelude as S
import RIO.ByteString as BS
import Data.Aeson
import RIO.ByteString.Lazy as LBS
import Resolver.Models.CfmmPool
import Dex.Models

consumerProps :: ConsumerProperties
consumerProps = brokersList ["0.0.0.0:9092"]
             <> groupId "random_id_1"
             <> noAutoCommit
             <> logLevel KafkaLogInfo

consumerSub :: Subscription
consumerSub = topics ["amm-topic"]
           <> offsetReset Earliest

runKafka :: RIO env ()
runKafka = liftIO $ do
    _   <- print "Running kafka stream..."
    C.bracket mkConsumer clConsumer runHandler
    where
      mkConsumer = newConsumer consumerProps consumerSub
      clConsumer (Left err) = return (Left err)
      clConsumer (Right kc) = maybe (Right ()) Left <$> closeConsumer kc
      runHandler (Left err) = print err >> pure ()
      runHandler (Right kc) = runF kc

-- -------------------------------------------------------------------

runF :: KafkaConsumer -> IO ()
runF consumer = S.drain $ S.repeatM $ pollMessageF consumer

pollMessageF :: KafkaConsumer -> IO (Maybe Pool)
pollMessageF consumer = do
    msg <- pollMessage consumer (Timeout 1000)
    _   <- print msg
    let parsedMsg = parseMessage msg
    _   <- print parsedMsg
    err <- commitAllOffsets OffsetCommit consumer
    _   <- print $ "Offsets: " <> maybe "Committed." show err
    pure parsedMsg

parseMessage :: Either e (ConsumerRecord k (Maybe BS.ByteString)) -> Maybe Pool
parseMessage x = case x of Right xv -> crValue xv >>= (\msg -> (decode $ LBS.fromStrict msg) :: Maybe Pool)
                           _ -> Nothing
