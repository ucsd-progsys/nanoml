{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
module NanoML.Eval where

import Control.Exception
import Control.Monad
import Control.Monad.Except
import Control.Monad.Fix
import Control.Monad.RWS   hiding (Alt)
import Text.Printf

import NanoML.Parser
import NanoML.Pretty
import NanoML.Types

import Debug.Trace

----------------------------------------------------------------------
-- Evaluation
----------------------------------------------------------------------

type Eval = ExceptT NanoError (RWST NanoOpts [Doc] EvalState IO)

            -- (WriterT [Doc] (StateT EvalState IO))

runEval :: NanoOpts -> Eval a -> IO (Either (NanoError, [Doc]) a)
runEval opts x = evalRWST (runExceptT x) opts initState >>= \case
  (Left e, tr) -> return $ Left (e, tr)
  (Right v, _) -> return $ Right v

runEvalFull :: NanoOpts -> Eval a -> IO (Either NanoError a, EvalState, [Doc])
runEvalFull opts x = runRWST (runExceptT x) opts initState

evalString :: MonadEval m => String -> m Value
evalString s = case parseExpr s of
  Left e  -> throwError (ParseError e)
  Right e -> eval e

evalDecl :: MonadEval m => Decl -> m ()
evalDecl decl = case decl of
  DFun _ Rec    binds  -> evalRecBinds binds >>= setVarEnv
  DFun _ NonRec binds  -> evalNonRecBinds binds >>= setVarEnv
  DTyp _ decls -> mapM_ addType decls
  DExn _ decl -> extendType "exn" decl

evalRecBinds :: MonadEval m => [(Pat,Expr)] -> m Env
evalRecBinds binds = do
  env <- gets stVarEnv
  mfix $ \fenv -> setVarEnv fenv >> foldr joinEnv env <$> evalBinds binds

evalNonRecBinds :: MonadEval m => [(Pat,Expr)] -> m Env
evalNonRecBinds binds = do
  env <- gets stVarEnv
  foldr joinEnv env <$> evalBinds binds

evalBinds :: MonadEval m => [(Pat,Expr)] -> m [Env]
evalBinds binds = mapM evalBind binds

-- | @evalBind (p,e) env@ returns the environment matched by @p@
evalBind :: MonadEval m => (Pat,Expr) -> m Env
evalBind (p,e) = logEnv $ do
  v <- eval e
  matchPat v p >>= \case
    Nothing  -> throwError $ MLException (mkExn "Match_failure" [])
    Just env -> return env

logEnv :: MonadEval m => m Env -> m Env
logEnv m = mycensor (\env w -> mkLog env) m
  where
  mkLog env = map (uncurry (=:)) (toListEnv env)

logMaybeEnv :: MonadEval m => m (Maybe Env) -> m (Maybe Env)
logMaybeEnv m = mycensor (\env w -> mkLog env) m
  where
  mkLog (Just env) = map (uncurry (=:)) (toListEnv env)
  mkLog _          = []

logExpr :: MonadEval m => Expr -> m Value -> m Value
logExpr (Var v) m = mycensor (\v w -> []) (tell [pretty (Var v)] >> m)
logExpr (Lit l) m = mycensor (\v w -> []) (tell [pretty (Lit l)] >> m)
logExpr (Lam p e) m = mycensor (\v w -> []) (tell [pretty (Lam p e)] >> m)
logExpr (Val v) m = mycensor (\v w -> []) (tell [pretty (Val v)] >> m)
logExpr e@(ConApp "[]" Nothing) m = mycensor (\v w -> []) (tell [pretty e] >> m)
logExpr expr m = mycensor (\v w -> [expr ==> v]) (tell [pretty expr] >> m)

mycensor :: MonadWriter w m => (a -> w -> w) -> m a -> m a
mycensor f m = pass $ do
    a <- m
    return (a, f a)

eval :: MonadEval m => Expr -> m Value
eval expr = logExpr expr $ case expr of
  Var v ->
    lookupEnv v =<< gets stVarEnv
  Lam _ _ ->
    VF . Func expr <$> gets stVarEnv
  App f args -> do
    vf    <- eval f
    vargs <- mapM eval args
    -- FIXME: this appears to be discarding bindings introduced by the
    -- function application
    foldM evalApp vf vargs
  Bop b e1 e2 -> do
    v1 <- eval e1
    v2 <- eval e2
    evalBop b v1 v2
  Uop u e -> do
    v <- eval e
    evalUop u v
  Lit l -> return (litValue l)
  Let Rec binds body -> do
    env <- evalRecBinds binds
    eval body `withEnv` env
  Let NonRec binds body -> do
    env <- evalNonRecBinds binds
    eval body `withEnv` env
  Ite eb et ef -> do
    vb <- eval eb
    case vb of
      VB True  -> eval et
      VB False -> eval ef
      _        -> typeError "if-then-else given a non-boolean"
  Seq e1 e2 ->
    eval e1 >> eval e2
  Case e as -> do
    v <- eval e
    evalAlts v as
  Tuple es -> do
    vs <- mapM eval es
    return (VT (length vs) vs (map typeOf vs))
  ConApp "()" Nothing -> return VU
  ConApp "[]" Nothing -> return (VL [] (TVar "a"))
  ConApp "::" (Just (Tuple [h,t])) -> do
    vh <- eval h
    vt <- eval t
    case vt of
      VL vt t -> do
        su <- unify t (typeOf vh)
        return (VL (vh:vt) (subst su t))
      _       -> typeError $ ":: expects a list, was given: " ++ show (pretty vt)
  ConApp dc Nothing -> do
    evalConApp dc Nothing
  ConApp dc (Just e) -> do
    v <- eval e
    evalConApp dc (Just v)
  Try e alts -> do
    env <- gets stVarEnv
    eval e `catchError` \e -> do
      setVarEnv env
      case e of
        MLException ex -> evalAlts ex alts
        _              -> throwError e
  Prim1 (P1 p f) e -> do
    v <- eval e
    x <- liftIO $ try $ evaluate (f v)
    case x of
      Right x -> x
      Left (PatternMatchFail _) ->
        typeError $ printf "invalid argument to %s: %s" p (show $ pretty v)
  Prim2 (P2 p f) e1 e2 -> do
    v1 <- eval e1
    v2 <- eval e2
    x <- liftIO $ try $ evaluate (f v1 v2)
    case x of
      Right x -> x
      Left (PatternMatchFail _) ->
        typeError $ printf "invalid arguments to %s: %s, %s"
                           p (show $ pretty v1) (show $ pretty v2)
  Val v -> return v

evalApp :: MonadEval m => Value -> Value -> m Value
evalApp f a = logExpr (App (Val f) [Val a]) $ case f of
  VF (Func (Lam p e) env) -> do
    Just pat_env <- matchPat a p
    eval e `withEnv` joinEnv pat_env env
  _ -> typeError "tried to apply a non-function"

evalConApp :: MonadEval m => DCon -> Maybe Value -> m Value
evalConApp dc v = do
  dd <- lookupDataCon dc
  -- unless (length args == length vs) $
  --   typeError (printf "%s expects %d arguments, but was given %d"
  --                     dc (length args) (length vs))
  case (dArg dd, v) of
    (Nothing, Nothing) -> return (VA dc v (typeDeclType $ dType dd))
    (Just a,  Just v)  -> do
      su <- unify a (typeOf v)
      let t = subst su $ typeDeclType $ dType dd
      return (VA dc (Just v) t)
    (Nothing, Just v) ->
      typeError (printf "%s was given unexpected arugment: %s"
                        dc (show v))
    (Just t, Nothing) ->
      typeError (printf "%s is missing expected arugment of type: %s"
                        dc (show t))


evalBop :: MonadEval m
        => Bop -> Value -> Value -> m Value
evalBop bop v1 v2 = logExpr (Bop bop (Val v1) (Val v2)) $ case bop of
  Eq     -> VB <$> eqVal v1 v2
  Neq    -> VB . not <$> eqVal v1 v2
  Lt     -> VB <$> ltVal v1 v2
  Le     -> (\x y -> VB (x || y)) <$> ltVal v1 v2 <*> eqVal v1 v2
  Gt     -> VB <$> gtVal v1 v2
  Ge     -> (\x y -> VB (x || y)) <$> gtVal v1 v2 <*> eqVal v1 v2
  Plus   -> plusVal v1 v2
  Minus  -> minusVal v1 v2
  Times  -> timesVal v1 v2
  Div    -> divVal v1 v2
  Mod    -> modVal v1 v2
  FPlus  -> plusVal v1 v2
  FMinus -> minusVal v1 v2
  FTimes -> timesVal v1 v2
  FDiv   -> divVal v1 v2

evalUop :: MonadEval m => Uop -> Value -> m Value
evalUop Neg (VI i) = return (VI (negate i))
evalUop FNeg (VD d) = return (VD (negate d))


ltVal (VI x) (VI y) = return (x < y)
ltVal (VD x) (VD y) = return (x < y)
ltVal x      y      = typeError "cannot compare ordering of non-numeric types"

gtVal (VI x) (VI y) = return (x > y)
gtVal (VD x) (VD y) = return (x > y)
gtVal x      y      = typeError "cannot compare ordering of non-numeric types"

plusVal (VI i) (VI j) = return $ VI (i+j)
plusVal (VD i) (VD j) = return $ VD (i+j)
plusVal _      _      = typeError "+ can only be applied to ints"

minusVal (VI i) (VI j) = return $ VI (i-j)
minusVal (VD i) (VD j) = return $ VD (i-j)
minusVal _      _      = typeError "- can only be applied to ints"

timesVal (VI i) (VI j) = return $ VI (i*j)
timesVal (VD i) (VD j) = return $ VD (i*j)
timesVal _      _      = typeError "* can only be applied to ints"

divVal (VI i) (VI j) = return $ VI (i `div` j)
divVal (VD i) (VD j) = return $ VD (i / j)
divVal _      _      = typeError "/ can only be applied to ints"

modVal (VI i) (VI j) = return $ VI (i `mod` j)
modVal _      _      = typeError "mod can only be applied to ints"

litValue :: Literal -> Value
litValue (LI i) = VI i
litValue (LD d) = VD d
litValue (LB b) = VB b
litValue (LC c) = VC c
litValue (LS s) = VS s
litValue LU     = VU

evalAlts :: MonadEval m => Value -> [Alt] -> m Value
evalAlts _ []
  = throwError $ MLException (mkExn "Match_failure" [])
evalAlts v ((p,g,e):as)
  = matchPat v p >>= \case
      Nothing  -> evalAlts v as
      Just bnd -> do newenv <- joinEnv bnd <$> gets stVarEnv
                     case g of
                      Nothing -> eval e `withEnv` newenv
                      Just g  ->
                        eval g `withEnv` newenv >>= \case
                          VB True  -> eval e `withEnv` newenv
                          VB False -> evalAlts v as

-- | If a @Pat@ matches a @Value@, returns the @Env@ bound by the
-- pattern.
matchPat :: MonadEval m => Value -> Pat -> m (Maybe Env)
-- NOTE: should be MonadEval m => m (Maybe Env) so we can throw exception on ill-typed pattern match
matchPat v p = logMaybeEnv $ case p of
  VarPat var ->
    return $ Just (insertEnv var v emptyEnv)
  LitPat lit ->
    return $ if matchLit v lit then Just emptyEnv else Nothing
  ConsPat p ps -> do
    (x,xs) <- unconsVal v
    menv1 <- matchPat x p
    menv2 <- matchPat xs ps
    case (menv1, menv2) of
      (Just env1, Just env2) -> return $ Just (joinEnv env1 env2)
      _                      -> return Nothing
  ListPat ps
    | VL vs t <- v
    , length ps == length vs
      -> fmap (foldr joinEnv emptyEnv) . (sequence :: [Maybe Env] -> Maybe [Env])
           <$> zipWithM matchPat vs ps
  TuplePat ps
    | VT n vs ts <- v
    , length ps == n
      -> fmap (foldr joinEnv emptyEnv) . (sequence :: [Maybe Env] -> Maybe [Env])
           <$> zipWithM matchPat vs ps
  WildPat ->
    return $ Just emptyEnv
  ConPat "[]" Nothing
    | VL [] t <- v
      -> return (Just emptyEnv)
    | VL _ t <- v
      -> return Nothing
  ConPat "()" Nothing
    | VU <- v
      -> return (Just emptyEnv)
  ConPat dc p
    | VA c v t <- v
    , dc == c
--    , length ps == length vs
      -> case (v,p) of
          (Nothing, Nothing) -> return (Just mempty)
          (Just v, Just p) -> matchPat v p
      -- fmap (foldr joinEnv emptyEnv) . (sequence :: [Maybe Env] -> Maybe [Env])
      --      <$> zipWithM matchPat vs ps
    | VA c vs t <- v
    , dc /= c
      -> return Nothing
  AsPat p x -> do
    Just env <- matchPat v p
    return (Just (insertEnv x v env))
  _ -> typeError (printf "type error: tried to match %s against %s"
                      (show $ pretty v) (show $ pretty p) :: String)

unconsVal :: MonadEval m => Value -> m (Value, Value)
unconsVal (VL (x:xs) t) = return (x, VL xs t)
unconsVal _             = typeError "type error: uncons can only be applied to lists"

matchLit :: Value -> Literal -> Bool
matchLit (VI i1) (LI i2) = i1 == i2
matchLit (VD d1) (LD d2) = d1 == d2
matchLit (VB b1) (LB b2) = b1 == b2
matchLit VU      LU      = True
matchLit _       _       = False


testEval :: String -> IO ()
testEval s = let Right e = parseExpr s
             in print =<< runEval stdOpts (eval e)
