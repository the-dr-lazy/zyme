{-|
Module      : Cascade.CLI.Data.Config
Description : !!! INSERT MODULE SHORT DESCRIPTION !!!
Copyright   : (c) 2020-2021 Cascade
License     : MPL 2.0
Maintainer  : Mohammad Hasani <the-dr-lazy@pm.me> (the-dr-lazy.github.io)
Stability   : Stable
Portability : POSIX

!!! INSERT MODULE LONG DESCRIPTION !!!
-}

module Cascade.CLI.Data.Config (ConfigP(..), PostgresConfigP(..), Partial, PostgresPartial, Final, PostgresFinal, finalize, def) where

import           Cascade.CLI.Data.Errors             ( Errors
                                                     , validateEmptyField
                                                     )
import           Cascade.CLI.Data.Model.FreePort     ( FreePort )
import qualified Cascade.CLI.Data.Model.FreePort    as FreePort
import           Data.Generics.Labels                ( )
import           Generic.Data                        ( Generically(..) )
import           Validation                          ( Validation )

data Phase = Partial | Final

type family Validate (p :: Phase) (raw :: Type) (parsed :: Type) where
  Validate 'Partial raw _ = Last raw
  Validate 'Final _ parsed = parsed

-- brittany-disable-next-binding
data PostgresConfigP (p :: Phase) = PostgresConfig
  { host     :: Validate p String String
  , port     :: Validate p Word16 Word16
  , user     :: Validate p String String
  , password :: Validate p String String
  , database :: Validate p String String
  } deriving stock Generic

type PostgresFinal = PostgresConfigP 'Final

type PostgresPartial = PostgresConfigP 'Partial

deriving stock instance Show PostgresFinal
deriving via Generically PostgresPartial instance Semigroup PostgresPartial
deriving via Generically PostgresPartial instance Monoid PostgresPartial

-- brittany-disable-next-binding
data ConfigP (p :: Phase) = Config
  { httpPort        :: Validate p Int FreePort
  , postgresConfig :: PostgresConfigP p
  } deriving stock Generic

type Final = ConfigP 'Final

type Partial = ConfigP 'Partial

deriving stock instance Show Final
deriving via Generically Partial instance Semigroup Partial
deriving via Generically Partial instance Monoid Partial

def :: Partial
def = Config
  { httpPort       = pure 3141
  , postgresConfig = PostgresConfig { host     = pure "localhost"
                                    , port     = pure 5432
                                    , user     = pure "cascade"
                                    , password = pure ""
                                    , database = pure "cascad-api"
                                    }
  }

finalizePostgres :: PostgresPartial -> IO (Validation Errors PostgresFinal)
finalizePostgres PostgresConfig {..} =
  let validateHost     = validateEmptyField host
      validatePort     = validateEmptyField port
      validateUser     = validateEmptyField user
      validatePassword = validateEmptyField password
      validateDatabase = validateEmptyField database
  in  pure <| PostgresConfig <$> validateHost <*> validatePort <*> validateUser <*> validatePassword <*> validateDatabase

finalize :: Partial -> IO (Validation Errors Final)
finalize Config {..} = do
  validateHttpPort       <- FreePort.mk httpPort
  validatePostgresConfig <- finalizePostgres postgresConfig
  pure <| Config <$> validateHttpPort <*> validatePostgresConfig
