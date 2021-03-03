{-|
Module      : Test.Cascade.Api.StateMachine.Command.Task
Description : !!! INSERT MODULE SHORT DESCRIPTION !!!
Copyright   : (c) 2020-2021 Cascade
License     : MPL 2.0
Maintainer  : Mohammad Hasani <the-dr-lazy@pm.me> (the-dr-lazy.github.io)
Stability   : Stable
Portability : POSIX

!!! INSERT MODULE LONG DESCRIPTION !!!
-}

module Test.Cascade.Api.StateMachine.Command.Task (commands) where

import           Cascade.Api.Test.Prelude
import qualified Cascade.Api.Data.Project           as Project
import qualified Cascade.Api.Data.Task              as Task
import           Cascade.Api.Data.OffsetDatetime     ( FormattedOffsetDatetime(..)
                                                     , unFormattedOffsetDatetime
                                                     )
import           Cascade.Api.Hedgehog.Gen.Prelude
import qualified Cascade.Api.Hedgehog.Gen.Text      as Gen
import qualified Cascade.Api.Hedgehog.Gen.Chronos   as Gen
import qualified Cascade.Api.Hedgehog.Gen.Id        as Gen
import qualified Cascade.Api.Network.TestClient.Api.Projects.Tasks
                                                    as Cascade.Api.Projects.Tasks
import qualified Cascade.Api.Network.TestClient.Api.Tasks
                                                    as Cascade.Api.Tasks
import           Control.Lens                        ( (?~)
                                                     , (^.)
                                                     , (^..)
                                                     , (%~)
                                                     , (^?)
                                                     , at
                                                     , to
                                                     , folded
                                                     , traversed
                                                     , cons
                                                     , sans
                                                     , non
                                                     , ix
                                                     , has
                                                     )
import           Servant.API.UVerb.Union             ( matchUnion )
import qualified Data.Map                           as Map
import qualified Cascade.Data.Text                  as Text
import qualified Cascade.Data.Text.NonEmpty         as Text.NonEmpty
import           Hedgehog
import qualified Hedgehog.Gen                       as Gen
import           Test.Cascade.Api.StateMachine.Model ( Model )
import qualified Cascade.Api.Servant.Response       as Response
import           Chronos                             ( offsetDatetimeToTime )

commands :: MonadGen g => GenBase g ~ Identity => MonadIO m => MonadTest m => [Command g m Model]
commands =
  [ createValidForExistingProject
  , createValidForNonExistingProject
  , createInvalid
  , getAllByProjectIdForExistingProject
  , getAllByProjectIdForNonExistingProject
  , addNotExistingId
  , getExistingById
  , getNotExistingById
  , updateExistingByIdValid
  , updateExistingByIdInvalid
  , updateNotExistingById
  , deleteExistingById
  , deleteNotExistingById
  ]

-- brittany-disable-next-binding
data Create (v :: Type -> Type) = Create
  { projectId  :: Var Project.Id v
  , creatable  :: Task.RawCreatable
  }
  deriving stock (Generic, Show)

instance HTraversable Create where
  htraverse f Create {..} = Create <$> htraverse f projectId <*> pure creatable

createValidForExistingProject :: forall g m . MonadGen g => GenBase g ~ Identity => MonadIO m => MonadTest m => Command g m Model
createValidForExistingProject =
  let generator :: Model Symbolic -> Maybe (g (Create Symbolic))
      generator model = case model ^. #project . #creatables . to Map.keys of
        []         -> Nothing
        projectIds -> Just $ do
          projectId  <- Gen.element projectIds
          title      <- Gen.nonEmptyText 30 Valid
          deadlineAt <- FormattedOffsetDatetime <$> Gen.deadline Valid
          let creatable = Task.RawCreatable { .. }
          pure $ Create { .. }

      execute :: Create Concrete -> m Task.Id
      execute (Create projectId creatable) = do
        label "[Task/Create Valid]"

        response              <- evalIO $ Cascade.Api.Projects.Tasks.create (concrete projectId) creatable

        Response.Created task <- (response ^. #responseBody) |> matchUnion @(Response.Created Task.Readable) |> evalMaybe

        let id = task ^. #id

        checkEqReadableRawCreatableTask task creatable

        response ^. #responseStatusCode . #statusCode === 201

        footnoteShow response

        pure id

      update :: Ord1 v => Model v -> Create v -> Var Task.Id v -> Model v
      update model (Create projectId creatable) id = model |> #task . #creatables . at projectId . non Map.empty . at id ?~ creatable
  in  Command generator execute [Update update]

createValidForNonExistingProject :: forall g m . MonadGen g => GenBase g ~ Identity => MonadIO m => MonadTest m => Command g m Model
createValidForNonExistingProject =
  let generator :: Model Symbolic -> Maybe (g (Create Symbolic))
      generator model = case model ^. #project . #notExistingIds of
        []         -> Nothing
        projectIds -> Just $ do
          projectId  <- Gen.element projectIds
          title      <- Gen.nonEmptyText 30 Valid
          deadlineAt <- FormattedOffsetDatetime <$> Gen.deadline Valid
          let creatable = Task.RawCreatable { .. }
          pure $ Create { .. }

      execute :: Create Concrete -> m Cascade.Api.Projects.Tasks.CreateResponse
      execute (Create projectId creatable) = evalIO $ Cascade.Api.Projects.Tasks.create (concrete projectId) creatable

      ensure :: Model Concrete -> Model Concrete -> Create Concrete -> Cascade.Api.Projects.Tasks.CreateResponse -> Test ()
      ensure _before _after _input response = do
        footnoteShow response

        response ^. #responseStatusCode . #statusCode === 404
  in  Command generator execute [Ensure ensure]

createInvalid :: forall g m . MonadGen g => GenBase g ~ Identity => MonadIO m => MonadTest m => Command g m Model
createInvalid =
  let generator :: Model Symbolic -> Maybe (g (Create Symbolic))
      generator model = case model ^. #project . #creatables . to Map.keys of
        []         -> Nothing
        projectIds -> Just $ do
          flag <- Gen.bool_
          let boolToValidity     = bool Invalid Valid
          let titleValidity      = boolToValidity flag
          let deadlineAtValidity = boolToValidity $ not flag
          projectId  <- Gen.element projectIds
          title      <- Gen.nonEmptyText 30 titleValidity
          deadlineAt <- FormattedOffsetDatetime <$> Gen.deadline deadlineAtValidity
          let creatable = Task.RawCreatable { .. }
          pure $ Create { .. }

      coverage :: Create Concrete -> m ()
      coverage (Create _ creatable) = do
        let flag = creatable ^. #title . to Text.null
        cover 5 "invalid deadline" flag
        cover 5 "empty title"      (not flag)

      execute :: Create Concrete -> m Cascade.Api.Projects.Tasks.CreateResponse
      execute input@(Create projectId creatable) = do
        label "[Task/Create Invalid]"
        coverage input

        evalIO $ Cascade.Api.Projects.Tasks.create (concrete projectId) creatable

      ensure :: Model Concrete -> Model Concrete -> Create Concrete -> Cascade.Api.Projects.Tasks.CreateResponse -> Test ()
      ensure _before _after _input response = do
        footnoteShow response

        (response ^. #responseBody) |> matchUnion @(Response.Unprocessable Task.RawCreatableValidationErrors) |> evalMaybe

        response ^. #responseStatusCode . #statusCode === 422
  in  Command generator execute [Ensure ensure]

-- brittany-disable-next-binding
data GetAllByProjectId (v :: Type -> Type) = GetAllByProjectId
  { projectId  :: Var Project.Id v
  }
  deriving stock (Generic, Show)

instance HTraversable GetAllByProjectId where
  htraverse f (GetAllByProjectId id) = GetAllByProjectId <$> htraverse f id

getAllByProjectIdForExistingProject :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
getAllByProjectIdForExistingProject =
  let
    generator :: Model Symbolic -> Maybe (g (GetAllByProjectId Symbolic))
    generator model = case model ^. #project . #creatables . to Map.keys of
      []         -> Nothing
      projectIds -> Just $ GetAllByProjectId <$> Gen.element projectIds

    require :: Model Symbolic -> GetAllByProjectId Symbolic -> Bool
    require model (GetAllByProjectId projectId) = model |> has (#task . #creatables . ix projectId)

    execute :: GetAllByProjectId Concrete -> m Cascade.Api.Projects.Tasks.GetAllByProjectIdResponse
    execute (GetAllByProjectId projectId) = do
      label "[Task/Get All By Project Id For Existing Project]"
      evalIO $ Cascade.Api.Projects.Tasks.getAllByProjectId (concrete projectId)

    ensure :: Model Concrete -> Model Concrete -> GetAllByProjectId Concrete -> Cascade.Api.Projects.Tasks.GetAllByProjectIdResponse -> Test ()
    ensure before _after (GetAllByProjectId projectId) response = do
      footnoteShow response

      Response.Ok readables <- (response ^. #responseBody) |> matchUnion @(Response.Ok [Task.Readable]) |> evalMaybe

      let tasks = before ^. #task . #creatables . at projectId . non Map.empty

      length readables === Map.size tasks

      for_ readables $ \task -> do
        let id = Var . Concrete $ task ^. #id

        task' <- Map.lookup id tasks |> evalMaybe

        checkEqReadableRawCreatableTask task task'
  in
    Command generator execute [Require require, Ensure ensure]

getAllByProjectIdForNonExistingProject :: forall g m . MonadGen g => GenBase g ~ Identity => MonadIO m => MonadTest m => Command g m Model
getAllByProjectIdForNonExistingProject =
  let
    generator :: Model Symbolic -> Maybe (g (GetAllByProjectId Symbolic))
    generator model = case model ^. #project . #notExistingIds of
      []         -> Nothing
      projectIds -> Just $ GetAllByProjectId <$> Gen.element projectIds

    execute :: GetAllByProjectId Concrete -> m Cascade.Api.Projects.Tasks.GetAllByProjectIdResponse
    execute (GetAllByProjectId projectId) = do
      label "[Task/Get All By Project Id For Non Existing Project]"
      evalIO $ Cascade.Api.Projects.Tasks.getAllByProjectId (concrete projectId)

    ensure :: Model Concrete -> Model Concrete -> GetAllByProjectId Concrete -> Cascade.Api.Projects.Tasks.GetAllByProjectIdResponse -> Test ()
    ensure _before _after _input response = do
      footnoteShow response

      response ^. #responseStatusCode . #statusCode === 404
  in
    Command generator execute [Ensure ensure]

-- brittany-disable-next-binding
data AddNotExistingId (v :: Type -> Type) = AddNotExistingId
  { id :: Task.Id
  }
  deriving stock Show

instance HTraversable AddNotExistingId where
  htraverse _ (AddNotExistingId id) = pure $ AddNotExistingId id

addNotExistingId :: forall g m . MonadGen g => Applicative m => Command g m Model
addNotExistingId =
  let generator :: Model Symbolic -> Maybe (g (AddNotExistingId Symbolic))
      generator _ = Gen.id |> fmap AddNotExistingId |> Just

      execute :: AddNotExistingId Concrete -> m Task.Id
      execute (AddNotExistingId id) = pure id

      update :: Model v -> AddNotExistingId v -> Var Task.Id v -> Model v
      update model _input id = model |> #task . #notExistingIds %~ cons id
  in  Command generator execute [Update update]

-- brittany-disable-next-binding
newtype GetById (v :: Type -> Type) = GetById
  { id :: Var Task.Id v
  }
  deriving stock (Generic, Show)

instance HTraversable GetById where
  htraverse f (GetById id) = GetById <$> htraverse f id

getExistingById :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
getExistingById =
  let generator :: Model Symbolic -> Maybe (g (GetById Symbolic))
      generator model = case model ^.. #task . #creatables . folded . to Map.keys |> mconcat of
        []  -> Nothing
        ids -> Gen.element ids |> fmap GetById |> Just

      require :: Model Symbolic -> GetById Symbolic -> Bool
      require model (GetById id) = model |> has (#task . #creatables . folded . ix id)

      execute :: GetById Concrete -> m Cascade.Api.Tasks.GetByIdResponse
      execute (GetById id) = do
        label "[Task/Get Existing By Id]"
        evalIO . Cascade.Api.Tasks.getById $ concrete id

      ensure :: Model Concrete -> Model Concrete -> GetById Concrete -> Cascade.Api.Tasks.GetByIdResponse -> Test ()
      ensure before _after _input response = do
        footnoteShow response

        Response.Ok task <- (response ^. #responseBody) |> matchUnion @(Response.Ok Task.Readable) |> evalMaybe

        let id = Var . Concrete $ task ^. #id

        creatable <- evalMaybe $ before ^? #task . #creatables . folded . ix id

        checkEqReadableRawCreatableTask task creatable
  in  Command generator execute [Require require, Ensure ensure]


getNotExistingById :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
getNotExistingById =
  let generator :: Model Symbolic -> Maybe (g (GetById Symbolic))
      generator model = case model ^. #task . #notExistingIds of
        []  -> Nothing
        ids -> Gen.element ids |> fmap GetById |> Just

      execute :: GetById Concrete -> m Cascade.Api.Tasks.GetByIdResponse
      execute input = do
        label "[Task/Get Non Existing By Id]"
        evalIO . Cascade.Api.Tasks.getById $ input ^. #id . concreted

      ensure :: Model Concrete -> Model Concrete -> GetById Concrete -> Cascade.Api.Tasks.GetByIdResponse -> Test ()
      ensure _before _after _input response = do
        footnoteShow response
        response ^. #responseStatusCode . #statusCode === 404
  in  Command generator execute [Ensure ensure]

-- brittany-disable-next-binding
data UpdateById (v :: Type -> Type) = UpdateById
  { id :: Var Task.Id v
  , updatable :: Task.RawUpdatable
  }
  deriving stock (Generic, Show)

instance HTraversable UpdateById where
  htraverse f (UpdateById {..}) = UpdateById <$> htraverse f id <*> pure updatable

updateExistingByIdValid :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
updateExistingByIdValid =
  let generator :: Model Symbolic -> Maybe (g (UpdateById Symbolic))
      generator model = case model ^.. #task . #creatables . folded . to Map.keys |> mconcat of
        []  -> Nothing
        ids -> Just $ do
          id         <- Gen.element ids
          title      <- Just <$> Gen.nonEmptyText 30 Valid
          deadlineAt <- Just . FormattedOffsetDatetime <$> Gen.deadline Valid
          let updatable = Task.RawUpdatable { .. }
          pure $ UpdateById { .. }

      require :: Model Symbolic -> UpdateById Symbolic -> Bool
      require model (UpdateById id _) = model |> has (#task . #creatables . folded . ix id)

      execute :: UpdateById Concrete -> m Cascade.Api.Tasks.UpdateByIdResponse
      execute UpdateById { id, updatable } = do
        label "[Task/Update Existing By Id Valid]"
        evalIO $ Cascade.Api.Tasks.updateById (concrete id) updatable

      ensure :: Model Concrete -> Model Concrete -> UpdateById Concrete -> Cascade.Api.Tasks.UpdateByIdResponse -> Test ()
      ensure _before _after input@(UpdateById _ updatable) response = do
        footnoteShow response

        let id = input ^. #id . concreted
        Response.Ok task <- (response ^. #responseBody) |> matchUnion @(Response.Ok Task.Readable) |> evalMaybe
        task ^. #id === id

        title <- updatable ^. #title |> evalMaybe
        task ^. #title . to Text.NonEmpty.un === title

        deadline <- updatable ^. #deadlineAt |> evalMaybe |> fmap unFormattedOffsetDatetime |> fmap offsetDatetimeToTime
        task ^. #deadlineAt . to unFormattedOffsetDatetime . to offsetDatetimeToTime === deadline

        response ^. #responseStatusCode . #statusCode === 200

      update :: Ord1 v => Model v -> UpdateById v -> Var Cascade.Api.Tasks.UpdateByIdResponse v -> Model v
      update model (UpdateById id updatable) _response =
        let creatable = updateCreatableTask updatable in model |> #task . #creatables . traversed %~ Map.adjust creatable id
  in  Command generator execute [Require require, Update update, Ensure ensure]

updateExistingByIdInvalid :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
updateExistingByIdInvalid =
  let generator :: Model Symbolic -> Maybe (g (UpdateById Symbolic))
      generator model = case model ^.. #task . #creatables . folded . to Map.keys |> mconcat of
        []  -> Nothing
        ids -> Just $ do
          flag <- Gen.bool_
          let boolToValidity     = bool Invalid Valid
          let titleValidity      = boolToValidity flag
          let deadlineAtValidity = boolToValidity $ not flag
          id         <- Gen.element ids
          title      <- Just <$> Gen.nonEmptyText 30 titleValidity
          deadlineAt <- Just . FormattedOffsetDatetime <$> Gen.deadline deadlineAtValidity
          let updatable = Task.RawUpdatable { .. }
          pure $ UpdateById { .. }

      require :: Model Symbolic -> UpdateById Symbolic -> Bool
      require model (UpdateById id _) = model |> has (#task . #creatables . folded . ix id)

      execute :: UpdateById Concrete -> m Cascade.Api.Tasks.UpdateByIdResponse
      execute UpdateById { id, updatable } = do
        label "[Task/Update Existing By Id Invalid]"
        evalIO $ Cascade.Api.Tasks.updateById (concrete id) updatable

      ensure :: Model Concrete -> Model Concrete -> UpdateById Concrete -> Cascade.Api.Tasks.UpdateByIdResponse -> Test ()
      ensure _before _after _input response = do
        footnoteShow response

        (response ^. #responseBody) |> matchUnion @(Response.Unprocessable Task.RawUpdatableValidationErrors) |> evalMaybe

        response ^. #responseStatusCode . #statusCode === 422
  in  Command generator execute [Require require, Ensure ensure]

updateNotExistingById :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
updateNotExistingById =
  let generator :: Model Symbolic -> Maybe (g (UpdateById Symbolic))
      generator model = case model ^. #task . #notExistingIds of
        []  -> Nothing
        ids -> Just $ do
          id         <- Gen.element ids
          title      <- Just <$> Gen.nonEmptyText 30 Valid
          deadlineAt <- Just . FormattedOffsetDatetime <$> Gen.deadline Valid
          let updatable = Task.RawUpdatable { .. }
          pure $ UpdateById { .. }

      execute :: UpdateById Concrete -> m Cascade.Api.Tasks.UpdateByIdResponse
      execute input@UpdateById { updatable } = do
        label "[Task/Update Non Existing By Id]"
        let id = input ^. #id . concreted
        evalIO $ Cascade.Api.Tasks.updateById id updatable

      ensure :: Model Concrete -> Model Concrete -> UpdateById Concrete -> Cascade.Api.Tasks.UpdateByIdResponse -> Test ()
      ensure _before _after _input response = do
        footnoteShow response
        response ^. #responseStatusCode . #statusCode === 404
  in  Command generator execute [Ensure ensure]

-- brittany-disable-next-binding
newtype DeleteById (v :: Type -> Type) = DeleteById
  { id :: Var Task.Id v
  }
  deriving stock (Generic, Show)

instance HTraversable DeleteById where
  htraverse f (DeleteById id) = DeleteById <$> htraverse f id

deleteExistingById :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
deleteExistingById =
  let generator :: Model Symbolic -> Maybe (g (DeleteById Symbolic))
      generator model = case model ^.. #task . #creatables . folded . to Map.keys |> mconcat of
        []  -> Nothing
        ids -> Gen.element ids |> fmap DeleteById |> Just

      require :: Model Symbolic -> DeleteById Symbolic -> Bool
      require model (DeleteById id) = model |> has (#task . #creatables . folded . ix id)

      execute :: DeleteById Concrete -> m Cascade.Api.Tasks.DeleteByIdResponse
      execute input = do
        label "[Task/Delete Existing By Id]"
        evalIO . Cascade.Api.Tasks.deleteById $ id
        where id = input ^. #id . concreted

      ensure :: Model Concrete -> Model Concrete -> DeleteById Concrete -> Cascade.Api.Tasks.DeleteByIdResponse -> Test ()
      ensure _before _after input response = do
        footnoteShow response
        Response.Ok task <- (response ^. #responseBody) |> matchUnion @(Response.Ok Task.Readable) |> evalMaybe
        task ^. #id === input ^. #id . concreted

      update :: Ord1 v => Model v -> DeleteById v -> Var Cascade.Api.Tasks.DeleteByIdResponse v -> Model v
      update model (DeleteById id) _response = model |> #task . #creatables . traversed %~ sans id
  in  Command generator execute [Require require, Update update, Ensure ensure]

deleteNotExistingById :: forall g m . MonadGen g => MonadIO m => MonadTest m => Command g m Model
deleteNotExistingById =
  let generator :: Model Symbolic -> Maybe (g (DeleteById Symbolic))
      generator model = case model ^. #task . #notExistingIds of
        []  -> Nothing
        ids -> Gen.element ids |> fmap DeleteById |> Just

      execute :: DeleteById Concrete -> m Cascade.Api.Tasks.DeleteByIdResponse
      execute input = do
        label "[Task/Delete Non Existing By Id]"
        let id = input ^. #id . concreted
        evalIO . Cascade.Api.Tasks.deleteById $ id

      ensure :: Model Concrete -> Model Concrete -> DeleteById Concrete -> Cascade.Api.Tasks.DeleteByIdResponse -> Test ()
      ensure _before _after _input response = do
        footnoteShow response
        response ^. #responseStatusCode . #statusCode === 404
  in  Command generator execute [Ensure ensure]

updateCreatableTask :: Task.RawUpdatable -> Task.RawCreatable -> Task.RawCreatable
updateCreatableTask updatable Task.RawCreatable {..} =
  Task.RawCreatable { title = fromMaybe title $ updatable ^. #title, deadlineAt = fromMaybe deadlineAt $ updatable ^. #deadlineAt }

checkEqReadableRawCreatableTask :: (MonadTest m, HasCallStack) => Task.Readable -> Task.RawCreatable -> m ()
checkEqReadableRawCreatableTask task creatable = do
  task ^. #title . to Text.NonEmpty.un === creatable ^. #title
  (task ^. #deadlineAt . to unFormattedOffsetDatetime . to offsetDatetimeToTime)
    === (creatable ^. #deadlineAt . to unFormattedOffsetDatetime . to offsetDatetimeToTime)
