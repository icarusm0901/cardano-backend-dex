module Resolver.KafkaClient (run) where

import Control.Exception as C (bracket) 
import Kafka.Consumer
import RIO
import Prelude (print)
import qualified Streamly.Prelude as S
import RIO.ByteString as BS
import Plutus.V1.Ledger.Tx ( TxOut(..) )
import Data.Aeson
import Resolver.Models.AppSettings
import RIO.ByteString.Lazy as LBS

-- Global consumer properties
consumerProps :: ConsumerProperties
consumerProps = brokersList ["0.0.0.0:9092"]
             <> groupId "random_id_1"
             <> noAutoCommit
             <> logLevel KafkaLogInfo

-- Subscription to topics
consumerSub :: Subscription
consumerSub = topics ["amm-topic"]
           <> offsetReset Latest

-- Running an example
run :: HasAppSettings env => RIO env ()
run = liftIO $ do
    res <- C.bracket mkConsumer clConsumer runHandler
    print res
    where
      mkConsumer = newConsumer consumerProps consumerSub
      clConsumer (Left err) = return (Left err)
      clConsumer (Right kc) = maybe (Right ()) Left <$> closeConsumer kc
      runHandler (Left err) = return ()
      runHandler (Right kc) = runF kc

-- -------------------------------------------------------------------

runF :: KafkaConsumer -> IO ()
runF consumer = S.drain $ S.repeatM $ pollMessageF consumer

pollMessageF :: KafkaConsumer -> IO (Maybe TxOut)
pollMessageF consumer = do
    msg <- pollMessage consumer (Timeout 1000)
    _   <- print msg
    let parsedMsg = parseMessage msg
    _   <- print parsedMsg
    err <- commitAllOffsets OffsetCommit consumer
    _   <- print $ "Offsets: " <> maybe "Committed." show err
    pure parsedMsg

parseMessage :: Either e (ConsumerRecord k (Maybe BS.ByteString)) -> Maybe TxOut
parseMessage x = case x of Right x -> (crValue x) >>= (\msg -> (decode $ LBS.fromStrict msg) :: Maybe TxOut)
                           _ -> Nothing