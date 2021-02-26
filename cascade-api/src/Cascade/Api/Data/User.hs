{-|
Module      : Cascade.Api.Data.User
Description : !!! INSERT MODULE SHORT DESCRIPTION !!!
Copyright   : (c) 2020-2021 Cascade
License     : MPL 2.0
Maintainer  : Mohammad Hasani <the-dr-lazy@pm.me> (the-dr-lazy.github.io)
Stability   : Stable
Portability : POSIX

!!! INSERT MODULE LONG DESCRIPTION !!!
-}

{-# LANGUAGE UndecidableInstances #-}
module Cascade.Api.Data.User
  ( User
  , Id
  , Username
  , EmailAddress
  , Password
  , Readable(..)
  , Creatable(..)
  , RawCreatableValidationErrors
  , parseRawCreatableUser
  ) where

import           Cascade.Api.Data.ByteString.Password
                                                     ( Password )
import qualified Cascade.Api.Data.Id                as Data
import           Cascade.Api.Data.Text.EmailAddress  ( EmailAddress )
import           Cascade.Api.Data.Text.Username      ( Username )
import           Cascade.Data.Validation
import qualified Cascade.Data.Validation            as Validation
import           Data.Aeson                          ( FromJSON
                                                     , ToJSON
                                                     )
import           Data.Generics.Labels                ( )
import qualified Polysemy

data User

type Id = Data.Id User

data Readable = Readable
  { id           :: Id
  , username     :: Username
  , emailAddress :: EmailAddress
  }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (FromJSON, ToJSON)

data Creatable v = Creatable
  { username     :: Validate v Text Username
  , emailAddress :: Validate v Text EmailAddress
  , password     :: Validate v Text Password
  }
  deriving stock Generic

deriving via (Generically (Creatable 'Parsed)) instance Validatable (Creatable 'Raw) (Creatable 'Parsed)

deriving stock instance Show (Creatable 'Raw)
deriving anyclass instance ToJSON (Creatable 'Raw)
deriving anyclass instance FromJSON (Creatable 'Raw)

type RawCreatableValidationErrors = (Validation.Errors (Creatable 'Raw) (Creatable 'Parsed))

parseRawCreatableUser :: Creatable 'Raw -> Validation RawCreatableValidationErrors (Creatable 'Parsed)
parseRawCreatableUser = Polysemy.run . validate
