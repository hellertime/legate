{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Legate.Options where

import           Control.Monad.Reader
import           Data.ByteString.Lazy.Char8 (ByteString)
import           Data.String
import           Network.Consul.Http
import           Network.Consul.Types
import           Options.Applicative

data CommandOpts a = CommandOpts {
  _globalOpts :: GlobalOpts,
  _commandOpts :: a
}

commandOptsParser :: Parser a -> Parser (CommandOpts a)
commandOptsParser pa = CommandOpts <$> globalOptsParser <*> pa

data GlobalOpts = GlobalOpts {
  _consulHost :: String,
  _consulPort :: Int,
  _consulSSL  :: Bool
}

defaultOpts :: GlobalOpts
defaultOpts = GlobalOpts "localhost" 8500 False

globalOptsParser :: Parser GlobalOpts
globalOptsParser = GlobalOpts <$> strOption host <*> option auto port <*> switch ssl
  where GlobalOpts {..} = defaultOpts
        host = long "consul-host" <> short 'H' <> value _consulHost <> showDefault
               <> help "host running consul" <> metavar "HOST"
        port = long "consul-port" <> short 'P' <> value _consulPort <> showDefault
               <> help "consul HTTP API port on HOST" <> metavar "PORT"
        ssl  = long "ssl" <> showDefault <> help "use https"

consulPath :: GlobalOpts -> String
consulPath (GlobalOpts host port ssl) = scheme ++ host ++ ":" ++ show port
  where scheme | ssl       = "https://"
               | otherwise = "http://"


fstr :: IsString a => ReadM a
fstr = fromString <$> str


registrator :: String -> Parser a -> Parser (Register a)
registrator thing p = Register <$> strOption name <*> optional (strOption thingid) <*> p
                      <|> DeRegister <$> strOption dereg
  where dereg = short 'd' <> help "name to deregister"
        thingid = long "id"   <> short 'i'
                  <> help ("identifier for this " ++ thing ++ ", if different from name")
        name    = long "name" <> short 'n' <> help ("name for this " ++ "thing")

svcParser :: Parser Service
svcParser = Service <$> many (option fstr tag)
                    <*> option auto port
                    <*> optional chkParser
  where
        tag   = long "tag"  <> short 't' <> help "tags for this service on this node"
        port  = long "port" <> short 'p' <> value 0 <> showDefault <> help "port this service runs on"

chkParser :: Parser Check
chkParser = TTL    <$> option fstr ttl <*> optional (option fstr notes)
            <|>
            Script <$> option fstr script <*> option fstr interval <*> optional (option fstr notes)
  where ttl      = long "ttl" <> help "time to live check duration"
        notes    = long "notes" <> help "human readable description of this check"
        script   = long "script" <> short 's' <> help "script to run for this check"
        interval = long "interval" <> value "10s" <> help "check interval for this script check"
                   <> showDefault

type Command a = (CommandOpts a -> IO ()) -> Mod CommandFields (IO ())

commander :: String -> String -> Parser a -> Command a
commander cmd desc p f = command cmd (info (helper <*> fmap f (commandOptsParser p))
                                      (progDesc desc))

svcCommand :: Command (Register Service)
svcCommand = commander "service" "register or deregister a service" $ registrator "service" svcParser

data Exec = Exec (Register Service) String

exParser :: Parser Exec
exParser = Exec <$> registrator "service" svcParser <*> strOption cmd
  where cmd = long "command" <> short 'e' <> help "command to run"

execCommand :: Command Exec
execCommand = commander "exec" "run a command wrapped in service registration" exParser

checkCommand :: Command (Register Check)
checkCommand = commander "check" "register or deregister a check" $ registrator "check" chkParser

kvParser :: Parser KV
kvParser = GetKey     <$> strArgument key
           <|> PutKey <$> strOption set <*> option fstr val
           <|> DelKey <$> strOption   del
  where key = metavar "KEY" <> help "key to get"
        set = long "key"    <> short 'k' <> metavar "KEY" <> help "key to set"
        val = long "set"    <> short 's' <> metavar "VALUE" <> help "value to set"
        del = long "delete" <> short 'd' <> metavar "KEY"   <> help "key to delete"

kvCommand :: Command KV
kvCommand = commander "kv" "get or set values in the key/value store" kvParser
