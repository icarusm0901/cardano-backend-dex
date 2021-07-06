module Executor.HttpClient 
    ( getUnspentOuts
    , getCurrentHeight
    ) where

import Executor.Models.Settings
import RIO as R
import Conduit ( (.|), runConduit )
import Network.HTTP.Req
import Network.HTTP.Req.Conduit ( responseBodySource )
import Prelude as P (print)
import Data.Default.Class ()
import Data.Conduit.Binary as B ()
import Data.Aeson ( eitherDecode, FromJSON )
import Text.URI ()
import Data.Conduit.Combinators as C ( map, mapM_ )
import RIO.ByteString.Lazy ( fromStrict )
import qualified RIO.ByteString.Lazy as BL
import RIO.Text as T ( pack )
import Data.List as L ( foldl )
import Plutus.V1.Ledger.Tx ( TxOut(..) )
import Dex.Models

-- ---------- Types declaration ----------

-- ---------- Utils functions ------------

baseGetReq :: forall a env . (FromJSON a, HasHttpSettings env) => [Text] -> RIO env a
baseGetReq reqPaths = do
    settings <- view httpSettingsL
    runReq defaultHttpConfig $ do
        let uri = L.foldl (/:) (http (T.pack $ hostS settings)) reqPaths
        r <- req GET uri NoReqBody jsonResponse (port $ portS settings)
        let result = responseBody r :: a
        pure result

basePostReq :: forall a b env . (FromJSON a, HasHttpSettings env, ToJSON b) => [Text] -> b -> RIO env a
basePostReq reqPaths model = do
    settings <- view httpSettingsL
    runReq defaultHttpConfig $ do
        let uri = L.foldl (/:) (http (T.pack $ hostS settings)) reqPaths
        _ <- req POST uri (ReqBodyJson model) jsonResponse (port $ portS settings)
        pure ()
-- ---------- Module api -----------------

resolvePoolReq :: HasHttpSettings env => RIO env (Maybe Pool)
resolvePoolReq = baseGetReq ["resolve"]

-- Get current chain height
sendPredicted :: HasHttpSettings env => Pool -> RIO env ()
sendPredicted pool = basePostReq ["pull"] pool

-- ---------- Experimental feature -------