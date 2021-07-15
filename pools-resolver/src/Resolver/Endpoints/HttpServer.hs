module Resolver.Endpoints.HttpServer
    ( HttpServer(..)
    , mkHttpServer
    ) where

import Resolver.Models.AppSettings as AppSettings
import Control.Monad.IO.Class as CIO (liftIO)
import RIO as RIO (Maybe, ($), (>>), RIO(..), view, liftIO)
import Dex.Models
import Resolver.Services.PoolsResolver (PoolResolver(..))
import Servant
import Network.Wai.Handler.Warp as Warp
import Prelude (print)
import Resolver.Models.CfmmPool
import Resolver.Services.PoolApi

data HttpServer env = HttpServer
    { runHttpServer :: HasHttpServerSettings env => RIO env () 
    }

mkHttpServer :: PoolResolver -> PoolApi -> HttpServer env
mkHttpServer r p = HttpServer $ runHttpServer' r p

runHttpServer' :: HasHttpServerSettings env => PoolResolver -> PoolApi -> RIO env ()
runHttpServer' r p = do
    settings <- view httpSettingsL
    RIO.liftIO $ print "Running http server" >> (Warp.run (AppSettings.getPort settings) (app r p))

-------------------------------------------------------------------------------------

type Api =
         "resolve" :> ReqBody '[JSON] PoolId :> Get '[JSON] (Maybe Pool)
    :<|> "update"  :> ReqBody '[JSON] Pool :> Post '[JSON] ()

apiProxy :: Proxy Api
apiProxy = Proxy

app :: PoolResolver -> PoolApi -> Application
app r p = serve apiProxy (server r p)

server :: PoolResolver -> PoolApi -> Server Api
server r p =
    resolvePool r :<|>
    update p
 
resolvePool :: PoolResolver -> PoolId -> Handler (Maybe Pool)
resolvePool PoolResolver{..} pId = 
    CIO.liftIO $ (print "Going to resolve pool") >> resolve pId

update :: PoolApi -> Pool -> Handler ()
update PoolApi{..} pool =
    CIO.liftIO $ putPredicted $ PredictedPool pool