{-
    The MIT License (MIT)
    
    Copyright (c) 2015 Mário Feroldi Filho

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
-}

module Translator where

import Data.Char
import Data.List
import Data.Maybe
import Expressions
import Token
import Ast
import Inst
import Parser


{-----------------------------
        Code Generator
-----------------------------}

execute :: [Token] -> Either String [String]
execute stack
  = let
      paragraphs :: Either String Asts
      paragraphs = parseEofs stack

      declarations :: [(String, Label)]
      declarations
        = defnConsts ++ let
            search [] = []
            search ((Def (Ident name) args body) : rest)
              = (name, searchLabel declarations $ parseAst body) : search rest

            search ((Assign (Decl var) value) : rest)
              = (var, searchLabel declarations $ parseAst value) : search rest

            search (_:rest)
              = search rest
          in
            case paragraphs of
              Right p
                -> search p
              Left msg
                -> []

      outcode
        = case paragraphs of
            Right p
              -> Right $ map parseAst p
            Left msg
              -> Left msg

    in
      case outcode of
        Right oc
          -> Right $ map (\x ->
                        let
                          string = (translate declarations x)
                        in
                          if isPrefixOf "#include" string
                            then
                              string
                            else
                              string ++ ";" {-Lambda-}) oc

        Left msg
          -> Left msg

genCode :: String -> Either String String
genCode stack
  = case (execute $ parseTokens stack) of
      Right clines
        -> Right $ "#include \"include/prelude.hpp\"\n"
                    ++ "\n"
                    ++ "int argc = 0;\n"
                    ++ "char** argv;\n\n"
                    ++ intercalate "\n" clines
                    ++ "\n\n"
                    ++ "int main( int _argc, char** _argv )\n"
                    ++ "{\n"
                    ++ "   argc = _argc;\n"
                    ++ "   argv = _argv;\n"
                    ++ "   try {\n"
                    ++ "     _main();\n"
                    ++ "   } catch( const ClimbuException& e ) {\n"
                    ++ "     std::cout << e.what() << std::endl << std::endl;\n"
                    ++ "     return 1;\n"
                    ++ "   }\n"
                    ++ "   return 0;\n"
                    ++ "}"

      Left msg
        -> Left msg

fromEither (Right x) = x
fromEither (Left x) = x

searchLabel :: [(String, Label)] -> Inst -> Label
searchLabel stack (CallFunction (PushVar "countlist") [a, b])
  = let
      l = foldl
          (\acc inst
             -> case acc of
                  UnknownLabel -> searchLabel stack inst
                  _ -> acc)
          UnknownLabel
          [a, b]
    in
      case l of
        UnknownLabel -> Custom ""
        _ -> List l

searchLabel stack (CallFunction (PushVar name) args)
  = let
      l = getdefn name stack
    in
      case l of
        UnknownLabel -> getLabel (PushVar name)
        _ -> l

searchLabel stack (PushVar var)
  = let
      l = getdefn var stack
    in
      case l of
        UnknownLabel -> getLabel (PushVar var)
        _ -> l

searchLabel stack (MakeSimpleList list)
  = let
      l = foldl
          (\acc inst
             -> case acc of
                  UnknownLabel -> searchLabel stack inst
                  _ -> acc)
          UnknownLabel
          list
    in
      case l of
        UnknownLabel -> Custom "auto"
        _ -> List l

searchLabel _ inst
  = getLabel inst

translate :: [(String, Label)] -> Inst -> String
translate stack inst
  = let
      trans = translate stack
      getLabelString = show . searchLabel stack
      getLabelString1 s = show . searchLabel s

    in
    case inst of
      DeclVar x ->
        x

      PushVar x ->
        x

      PushConst x ->
        x

      PushConstf x ->
        x

      PushChar x ->
        if x == '\''
          then
            "'\\''"
          else
            ['\'', x, '\'']

      PushString x ->
        "\"" ++ x ++ "\""

      ImportInst path ->
        "#include \"include/" ++ path ++ "\""

      NegateInst x ->
        "(-" ++ trans x ++ ")"

      AssignTo i1 i2 ->
        case i1 of
          TupleInst list ->
            let
              parseTuple (_, Ignore) = []
              parseTuple (n, var) = "auto " ++ (trans var) ++ " = get<" ++ show n ++ ">(" ++ (trans i2) ++ ")"

            in
              intercalate ";\n" . filter (not . null) . map parseTuple . zip [0..] $ list

          MakeSimpleList list ->
            let
              parseList (_, Ignore) = []
              parseList (n, PushVar var) = trans . AssignTo (DeclVar var) . DoTake i2 . PushConst . show $ n

            in
              intercalate ";\n" . filter (not . null) . map parseList . zip [0..] $ list

          ListPMInst heads rtail ->
            let
              hInst = trans $ AssignTo (MakeSimpleList heads) i2
              tInst = trans $ AssignTo rtail ( CallFunction (PushVar "takeSince") [i2, PushConst . show . length $ heads] )

            in
              hInst ++ ";\n" ++ tInst

          DeclVar var ->
            (getLabelString i2) ++ " " ++ var ++ " = " ++ (trans i2)

          otherinst ->
            trans i1 ++ " = " ++ trans i2

      Operation op i1 i2 ->
        (trans i1) ++ op ++ (if op == "/" then "(float)" else []) ++ (trans i2)

      -- TOFIX
      ForList fresult range fcondition ->
        trans $ CallFunction (PushVar "eachlist") [fresult, range, fcondition]

      MakeCountList a b ->
        trans $ CallFunction (PushVar "countlist") [a, b]

      Cast (MakeSimpleList content) t ->
        t ++ "{" ++ (intercalate "," $ map trans content) ++ "}"

      msl @ (MakeSimpleList content) ->
        getLabelString msl ++ "{" ++ (intercalate "," $ map trans content) ++ "}"

      Block i ->
        "(" ++ (trans i) ++ ")"

      --"if(" ++ (trans statif) ++ "){" ++ (trans statthen) ++ ";}else{" ++ (trans statelse) ++ ";};"
      MakeCondition statif statthen statelse ->
        "((" ++ (trans statif) ++ ")?(" ++ (trans statthen) ++ "):(" ++ (trans statelse) ++ "))"

      Function name args body ->
        let
          strname = trans name
          checkName = if strname == "main" then "_main" else strname

          -- Sets local variables' types
          localVars'stack = giveCustomTypes args ++ stack

          --line = trans $ AssignTo (PushVar checkName) (Lambda args body)
          line
            =  genGenericPrefix (if args /= [TNothing] then length args else 0) args
            ++ getLabelString1 localVars'stack body
            ++ " "
            ++ checkName
            ++ genGenericArguments localVars'stack args
            ++ "{ return "
            ++ (translate localVars'stack body)
            ++ "; }"
        in
          line

      Lambda args body ->
        "[&](" ++ (intercalate "," $ map (\x -> "auto "++(trans x)) args) ++ "){ return " ++ (trans body) ++ "; }"

      CallFunction name args ->
        (trans name) ++ "(" ++ (intercalate "," $ map trans args) ++ ")"

      DoTake i1 i2 ->
        (trans i1) ++ "[" ++ (trans i2) ++ "]"

      ConcatList i1 i2 ->
        trans $ CallFunction (PushVar "conc") [i1, i2]

      DoStack expressions ->
        "[&](){ " ++ (intercalate ";" . map trans . init $ expressions) ++ ";\nreturn " ++ (trans $ last expressions) ++ ";}()"

      TupleInst i ->
        trans $ CallFunction (PushVar "make_tuple") i

      AndInst a b ->
        "AND(" ++ trans a ++ "," ++ trans b ++")"

      OrInst a b ->
        "OR(" ++ trans a ++ "," ++ trans b ++")"

      TryInst x ->
        "try{" ++ trans x ++ ";}catch(const ClimbuException & e){std::cout << e.what() << std::endl; abort();}"

      Cast a t ->
        "cast<" ++ t ++ ">(" ++ trans a ++ ")"

      Error msg ->
        error msg


genGenericPrefix n args
  = let
      prefix = "template<"
      suffix = "> "
      classes = map (\(PushVar (x:xs)) -> "class " ++ [toUpper x] ++ xs) args

      completePrefix
        =  prefix
        ++ (intercalate ", " classes)
        ++ suffix

    in
      if n /= 0
        then
          completePrefix
        else
          " "

genGenericArguments stack args
  = let
      prefix = "("
      suffix = ")"
      classes
        = if args /= [TNothing]
            then
              map (\(PushVar (x:xs)) -> [toUpper x] ++ xs) args
            else
              []

      completeArguments
        =  prefix
        ++ intercalate ", " (map (\(a, b) -> unwords [a, b]) $ zip classes (map (translate stack) args))
        ++ suffix

    in
      completeArguments

giveCustomTypes :: Insts -> [(String, Label)]
giveCustomTypes args
  = map
    (\(PushVar x, n) -> (x, Custom $ "t" ++ show n)) $ zip args [1..]

defnConsts
  = [ ("true", BoolLabel)
    , ("false", BoolLabel)
    , ("Undefined", SpecialLabel)
    , ("NaN", SpecialLabel)
    , ("Infinite", SpecialLabel)
    , ("NuL", SpecialLabel)
    , ("NuT", SpecialLabel)
    , ("NuS", SpecialLabel)
    , ("Null", SpecialLabel)
    , ("Void", SpecialLabel)
    ]

defnCallFun
  = [ ("print", SpecialLabel)
    , ("println", SpecialLabel)
    , ("puts", SpecialLabel)
    , ("putc", SpecialLabel)
    , ("mkstr", List CharLabel)
    , ("sum", IntLabel)
    , ("product", IntLabel)
    , ("elem", BoolLabel)
    , ("getLine", List CharLabel)
    , ("sqrt", DoubleLabel)
    , ("Char", CharLabel)
    , ("Int", IntLabel)
    , ("Float", FloatLabel)
    , ("Double", DoubleLabel)
    , ("Bool", BoolLabel)
    ]

getdefn var db
  = let
      gdc (Just c) = c
      gdc Nothing = UnknownLabel

    in
      gdc $ lookup var db

data Label
  = IntLabel
  | FloatLabel
  | DoubleLabel
  | CharLabel
  | BoolLabel
  | List Label
  | SpecialLabel
  | Custom String
  | UnknownLabel
  deriving(Eq, Read)

instance Show Label
  where
    show IntLabel = "int"
    show FloatLabel = "float"
    show DoubleLabel = "double"
    show CharLabel = "char"
    show BoolLabel = "bool"
    show (List CharLabel) = "String"
    show (List UnknownLabel) = "auto"
    show (List label) = "List<" ++ show label ++ ">"
    show SpecialLabel = "SpecialDate_t"
    show (Custom xs) = xs
    show UnknownLabel = "auto"

getLabel :: Inst -> Label
getLabel expr
  = case expr of
      Lambda _ _ ->
        UnknownLabel

      PushConst _ ->
        IntLabel

      PushConstf _ ->
        FloatLabel

      PushChar _ ->
        CharLabel

      MakeSimpleList x ->
        List $ foldl
               (\acc inst
                  -> case acc of
                      UnknownLabel -> getLabel inst
                      _ -> acc)
               UnknownLabel
               x

      MakeCountList a b ->
        List $ foldl
               (\acc inst
                  -> case acc of
                      UnknownLabel -> getLabel inst
                      _ -> acc)
               UnknownLabel
               [a, b]

      CallFunction (PushVar "countlist") args ->
        List $ foldl
               (\acc inst
                  -> case acc of
                      UnknownLabel -> getLabel inst
                      _ -> acc)
               UnknownLabel
               args

      MakeCondition _ x y ->
        if getLabel x == UnknownLabel
          then
            getLabel y
          else
            getLabel x

      ForList x _ _ ->
        getLabel x

      ConcatList x _ ->
        getLabel x

      PushVar x ->
        getdefn x defnConsts

      CallFunction (PushVar x) _ ->
        getdefn x defnCallFun

      DoStack x ->
        getLabel $ last x

      Operation operator a b ->
        case operator of
          ">" -> BoolLabel
          "<" -> BoolLabel
          ">=" -> BoolLabel
          "<=" -> BoolLabel
          "==" -> BoolLabel
          "!=" -> BoolLabel
          "%" -> IntLabel
          "+" -> FloatLabel
          "-" -> FloatLabel
          "*" -> FloatLabel
          "/" -> FloatLabel
          _ ->
            let
              alabel = getLabel a
              blabel = getLabel b
            in
              if alabel == IntLabel
                then
                  if blabel == IntLabel
                    then IntLabel
                    else FloatLabel
                else alabel

      Block x ->
        getLabel x

      TryInst x ->
        getLabel x

      Cast _ x ->
        Custom x

      _ ->
        UnknownLabel

typeChecker :: Inst -> String
typeChecker expression
  = show $ getLabel expression