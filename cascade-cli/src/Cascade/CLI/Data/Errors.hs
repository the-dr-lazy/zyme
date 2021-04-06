{-|
Module      : Cascade.CLI.Data.Errors
Description : !!! INSERT MODULE SHORT DESCRIPTION !!!
Copyright   : (c) 2020-2021 Cascade
License     : MPL 2.0
Maintainer  : Mohammad Hasani <the-dr-lazy@pm.me> (the-dr-lazy.github.io)
Stability   : Stable
Portability : POSIX

!!! INSERT MODULE LONG DESCRIPTION !!!
-}

module Cascade.CLI.Data.Errors (Errors, Error(..)) where

data Error = BusyHttpPortError
  deriving stock (Show, Eq)

type Errors = NonEmpty Error
