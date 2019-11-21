@create $root_class named MOO-Grapevine Network Bridge:MOO-Grapevine Network Bridge,Network Bridge,Bridge,Network,mgnb
@prop mgnb."host" 0 rc
@prop mgnb."port" 0 rc
@prop mgnb."connection" 0 rc
@prop mgnb."last_heartbeat" 0 rc
@prop mgnb."client_secret" 0 ""
@prop mgnb."client_id" 0 ""
@prop mgnb."version" "2.3.0" rc
@prop mgnb."default_channels" {} rc
@prop mgnb."supports" {} rc
@prop mgnb."refs" 0 c
@prop mgnb."ref_purge_time" 10 rc
@prop mgnb."online_games" 0 rc
@prop mgnb."announce_player_connections" 0 rc
@prop mgnb."event_throttles" 0 rc
@prop mgnb."connected_players" 0 rc
@prop mgnb."debuggers" {} rc
;;mgnb = player:my_match_object("mgnb"); mgnb.("supports") = {"channels", "players", "tells", "games"}; mgnb.("default_channels") = {"gossip", "moo"}; mgnb.("online_games") = mgnb.("connected_players") = mgnb.("refs") = mgnb.("event_throttles") = [];
@verb mgnb:"parse_server_messages" this none this
@program mgnb:parse_server_messages
(caller == this) || raise(E_PERM);
conn = this.connection;
if (conn in connected_players(1))
  ret_parsed = {};
  decoded = "";
  while (typeof(ret = `read(conn) ! ANY') != ERR)
    for x in (decode_binary(ret))
      if (x == 10)
        ret_parsed = {@ret_parsed, decoded};
        decoded = "";
      elseif (typeof(x) == STR)
        decoded = decoded + x;
      endif
    endfor
    for x in (ret_parsed)
      message = parse_json(x);
      if (is_member("event", mapkeys(message)))
        event_verb = "_event_" + message["event"];
        this:debug("Received event '", message["event"], ".");
        if (respond_to(this, event_verb))
          this:Debug("Handling event (verb=", event_verb, ")");
          set_task_local(message);
          try
            this:(event_verb)();
          except e (ANY)
            this:debug("Error with ", this, ":", event_verb, " > ", toliteral(e));
          endtry
        else
          this:debug("No handler for ", message["event"], " found. Ignoring.");
        endif
      endif
    endfor
    ret_parsed = {};
  endwhile
else
  raise(E_INVARG, "Connection is not open.");
endif
.
@verb mgnb:"_event_heartbeat" this none this
@program mgnb:_event_heartbeat
(caller == this) || raise(E_PERM);
this:send_event("heartbeat", ["players" -> $list_utils:map_property(connected_players(), "name")]);
for v, k in (this.refs)
  if (v["sent_time"] >= this.ref_purge_time)
    this.refs = mapdelete(this.refs, k);
  endif
  yin();
endfor
this.last_heartbeat = time();
.
@verb mgnb:"send" this none this
@program mgnb:send
caller_perms().wizard || raise(E_PERM);
{message} = args;
if ((this.connection in connected_players(1)) == 0)
  return E_INVARG;
endif
crlf = "~0D~0A";
if (typeof(message) == MAP)
  message = generate_json(message);
endif
if ((length(message) > 3) && (message[$ - 2..$] != "~0A"))
  message = message + crlf;
endif
return notify(this.connection, message);
.
@verb mgnb:"ref" this none this
@program mgnb:ref
(caller == this) || raise(E_PERM);
ref = string_hash(random_bytes(20), "md5");
event = `task_local()["message"] ! ANY';
if (event)
  event["sent_time"] = time();
  this.refs[ref] = event;
endif
return ref;
.
@verb mgnb:"send_event send_event_throttled" this none this
@program mgnb:send_event
caller_perms().wizard || raise(E_PERM);
{event_name, payload, ?ref = 0, ?throttle_time} = args;
this:debug("Sending ", event_name, " (payload=", toliteral(payload), ", ref=", ref, ")");
"Now with a basic throttling system!";
throttled = verb == "send_event_throttled";
if (throttled)
  if (this.event_throttles:has_key(event_name))
    if ((time() - this.event_throttles[event_name]) < throttle_time)
      this:debug("Throttled ", event_name, ".");
      return E_PERM;
    else
      this.event_throttles = mapdelete(this.event_throttles, event_name);
    endif
  endif
endif
message = ["event" -> event_name];
if (payload)
  message["payload"] = payload;
endif
if (ref)
  t = task_local();
  t["message"] = message;
  set_task_local(t);
  message["ref"] = this:ref();
endif
if (throttled)
  this.event_throttles[event_name] = time();
endif
return this:send(message);
.
@verb mgnb:"do_connect" this none this
@program mgnb:do_connect
(caller == this) || raise(E_PERM);
if (this.connection in connected_players(1))
  raise(E_NONE, "Already listening on socket.");
endif
conn = $network:open(this.host, this.port);
if (conn in connected_players(1))
  set_connection_option(conn, "hold-input", 1);
  set_connection_option(conn, "binary", 1);
  set_connection_option(conn, "disable-oob", 1);
  this.connection = conn;
  set_task_local(`mapdelete(task_local(), "reconnect") ! ANY => task_local()');
  return conn;
else
  return E_INVARG;
endif
.
@verb mgnb:"do_start" this none this
@program mgnb:do_start
caller_perms().wizard || raise(E_PERM);
"This is the verb that is responsible for handling starting and maintaining the Grapevine interface.";
"Clear cached data prior to connecting.";
this.online_games = this.connected_players = [];
"First, we need to connect to the port.";
this:debug("Opening connection to ", this.host, ":", this.port);
this:do_connect();
this:debug("Connected.");
"IF we got to this point, a connection has been made.";
"As such, we need to authenticate ourselves and handle any other post-connect routines...";
this:Debug("Performing post-connect routine.");
this:do_post_connect();
this:Debug("Post connect routine complete.");
"Now, parse inbound messages for the lifetime of the connection.";
this:debug("Entering parse loop.");
this:parse_server_messages();
this:debug("Shutting down...");
if (`recon = task_local()["reconnect"] ! ANY')
  if (!is_member("attempts", mapkeys(recon)))
    recon["attempts"] = 1;
  endif
  attempts = recon["attempts"];
  this:Debug("Attempting to reconnect.");
  while (attempts < recon["max_attempts"])
    suspend(`recon["wait"] ! ANY => 15');
    this:do_start();
    this:debug("Connection attempt failed. (", attempts, "/", recon["max_attempts"], ")");
  endwhile
  set_task_local(["reconnect" -> recon]);
  this:debug("Giving up. Goodbye.");
endif
.
@verb mgnb:"do_post_connect" this none this
@program mgnb:do_post_connect
(caller == this) || raise(E_PERM);
"Send our authenticate event.";
payload = ["channels" -> this.default_channels, "user_agent" -> this:user_agent(), "client_id" -> this.client_id, "client_secret" -> this.client_secret, "supports" -> this.supports, "version" -> this.version];
return this:send_event("authenticate", payload);
.
@verb mgnb:"user_agent" this none this
@program mgnb:user_agent
return tostr("LambdaMOO-ToastStunt ", server_version());
.
@verb mgnb:"_event_authenticate" this none this
@program mgnb:_event_authenticate
params = task_local();
if (is_member("status", mapkeys(params)) && (params["status"] == "success"))
  this:debug("Successfully authenticated.");
  $wiz_utils:announce("Successfully authenticated to the Grapevine network.", "miscellaneous");
  "Request the current list of online games and their players now that we're authenticated...";
  fork (0)
    this:send_event("games/status", [], 1);
    this:send_event("players/status", [], 1);
  endfork
else
  this:debug("Failed to authenticate...closing connection.");
  $wiz_utils:announce("Failed to authenticate to the Grapevine network.", "miscellaneous");
  "Give up";
  boot_player(this.connection);
endif
.
@verb mgnb:"is_connected" this none this rxd
@program mgnb:connected
return this.connection in connected_players(1);
.
@verb mgnb:"user_disconnected user_client_disconnected" this none this
@program mgnb:user_disconnected
if (caller == $sysobj)
  user = args[1];
  this:send_event("players/sign-out", ["name" -> user.name], 1);
endif
.
@verb mgnb:"user_connected user_created" this none this
@program mgnb:user_connected
if (caller == $sysobj)
  user = args[1];
  this:send_event("players/sign-in", ["name" -> user.name], 1);
endif
.
@verb mgnb:"find_event_ref" this none this
@program mgnb:find_event_ref
(caller == this) || raise(E_PERM);
return `this.refs[args[1]] ! ANY => 0';
.
@verb mgnb:"_event_players/sign-in" this none this
@program mgnb:_event_players/sign-in
(caller == this) || raise(E_PERM);
t = task_local();
if ((is_member("ref", mapkeys(t)) && this:find_event_ref(t["ref"])) || (is_member("status", mapkeys(t)) && (t["status"] == "success")))
  "Something from ourselves.";
  return;
endif
t = t["payload"];
if (this.announce_player_connections)
  this:local_announce(tostr("[", t["game"], "] ", t["name"], " has logged in."));
endif
this.connected_players[t["game"]] = setadd(this.connected_players[t["game"]], t["name"]);
.
@verb mgnb:"_event_players/sign-out" this none this
@program mgnb:_event_players/sign-out
(caller == this) || raise(E_PERM);
t = task_local();
if ((t:has_key("ref") && this:find_event_ref(t["ref"])) || (t:has_key("status") && (t["status"] == "success")))
  "Something from ourselves.";
  return;
endif
t = t["payload"];
if (this.announce_player_connections)
  this:local_announce(tostr("[", t["game"], "] ", t["name"], " has logged out."));
endif
this.connected_players[t["game"]] = setremove(this.connected_players[t["game"]], t["name"]);
.
@verb mgnb:"local_announce" this none this
@program mgnb:local_announce
(caller == this) || raise(E_PERM);
"Handles announcing events to the local game.";
.
@verb mgnb:"_event_games/status" this none this
@program mgnb:_event_games/status
(caller == this) || raise(E_PERM);
t = task_local();
if ((sent = this:find_event_ref(t["ref"])) && (t["event"] == sent["event"]))
  t = t["payload"];
  this.online_games[t["game"]] = mapdelete(t, "game");
endif
.
@verb mgnb:"_event_games/connect" this none this
@program mgnb:_event_games/connect
(caller == this) || raise(E_PERM);
t = task_local();
game = t["payload"]["game"];
"Retrieve game info and initially populate it's players.";
return this:send_event("games/status", ["game" -> game], 1) && this:send_event("players/status", ["game" -> game], 1);
.
@verb mgnb:"_event_games/disconnect" this none this
@program mgnb:_event_games/disconnect
(caller == this) || raise(E_PERM);
t = task_local();
game = t["payload"]["game"];
this.online_games = mapdelete(this.online_games, game);
this.connected_players = mapdelete(this.connected_players, game);
.
@verb mgnb:"_event_channels/broadcast" this none this
@program mgnb:_event_channels/broadcast
(caller == this) || raise(E_PERM);
t = task_local();
msg = t["payload"];
{channel, game, sender, message} = {msg["channel"], msg["game"], msg["name"], msg["message"]};
"Remove this comment and insert the code for channel announcements for your MOO.";
.
@verb mgnb:"_event_players/status" this none this
@program mgnb:_event_players/status
(caller == this) || raise(E_PERM);
t = task_local();
if ((sent = this:find_event_ref(t["ref"])) && (t["event"] == sent["event"]))
  t = t["payload"];
  this.connected_players[t["game"]] = t["players"];
endif
.
@verb mgnb:"server_started" this none this
@program mgnb:server_started
if (caller_perms().wizard)
  this:do_start();
endif
.
@verb mgnb:"_event_channels/subscribe" this none this rxd
@program mgnb:_event_channels/subscribe
(caller == this) || raise(E_PERM);
t = task_local();
if (!is_member("ref", mapkeys(t)))
  return 0;
endif
e = this:find_event_ref(t["ref"]);
if (e)
  "Spec says there's only status when it's failure, so:";
  if (is_member("status", mapkeys(t)) && (t["status"] == "failure"))
    this:debug("Failed to subscribe to channel '", e["payload"]["channel"], "': ", t["error"]);
  else
    this:debug("Subscribed to channel '", e["payload"]["channel"], "'.");
  endif
endif
.
@verb mgnb:"_event_channels/unsubscribe" this none this rxd
@program mgnb:_event_channels/unsubscribe
(caller == this) || raise(E_PERM);
t = task_local();
if (!is_member("ref", mapkeys(t)))
  return 0;
endif
e = this:find_event_ref(t["ref"]);
if (e)
  if (is_member("status", mapkeys(t)) && (t["status"] == "failure"))
    this:debug("Failed to unsubscribe from channel '", e["payload"]["channel"], "': ", t["error"]);
  else
    this:debug("Unsubscribed from channel '", e["payload"]["channel"], "'.");
  endif
endif
.
@verb mgnb:"_event_restart" this none this rxd
@program mgnb:_event_restart
(caller == this) || raise(E_PERM);
t = task_local();
downtime = t["payload"]["downtime"];
this:debug("Restart iminent. Expected downtime: ", $su:from_seconds(downtime));
"Set task local so we reconnect.";
t["reconnect"] = ["max_attempts" -> 3, "wait" -> downtime + random(2)];
set_task_local(t);
"Insert further code for handling restarts here.";
.
@verb mgnb:"init_for_core" this none this rxd
@program mgnb:init_for_core
if (caller_perms().wizard)
  this.connection = this.port = this.host = this.client_secret = this.client_id = 0;
  this.online_games = this.connected_players = this.refs = [];
endif
.
@verb mgnb:"debug" this none this
@program mgnb:debug
(caller == this) || raise(E_PERM);
if (this.debuggers)
  for x in (this.debuggers)
    x:is_listening() && x:tell("[Grapevine] ", @args);
  endfor
endif
.
@verb mgnb:"do_stop" this none this
@program mgnb:do_stop
caller_perms().wizard || raise(E_PERM);
if ((this.connection in connected_players(1)) == 0)
  return E_INVARG;
endif
boot_player(this.connection);
.
@verb mgnb:"initial_setup" this none this
@program mgnb:initial_setup
if (!caller_perms().wizard)
  return player:tell("A wizard must run this verb.");
elseif ((this.client_id != 0) && ($command_utils:yes_or_no("Setup already appears to have been ran. Do you wish to overwrite the existing values?") != 1))
  return player:tell("Aborted.");
endif
if ($command_utils:yes_or_no(("Do you wish to begin setting up your connection to Grapevine? This will corify this object (" + $string_utils:nn(this)) + ") as '$grapevine' and ask you obligatory questions for authentication.") == 1)
  if ($object_utils:has_property(#0, "grapevine"))
    if ($command_utils:yes_or_no(("#0.grapevine already exists and is currently pointing to " + toliteral($grapevine)) + ". Do you wish to overwrite it?") == 0)
      player:tell("Not overwriting #0.grapevine; please consider corifying it later.");
    else
      $grapevine = this;
    endif
  else
    add_property(#0, "grapevine", this, {player, "r"});
  endif
  ($grapevine == this) && player:tell("Corified ", this, " as $grapevine.");
  player:tell("You will now be asked a few obligatory questions to set up your connection to Grapevine.");
  player:tell("First, what is the hostname or IP address that your TCP-websocket bridge is listening on? Hit enter for '127.0.0.1'.");
  host = $string_utils:trim($command_utils:read());
  if (!host)
    host = "127.0.0.1";
  endif
  player:tell("Now, please enter the port number that your TCP-Websocket bridge is listening on. Hit enter for 8081.");
  port = $string_utils:trim($command_utils:read());
  if (!port)
    port = "8081";
  endif
  while (!$string_utils:is_numeric(port))
    player:tell("You must enter a valid port number in between 1-65535.");
    player:tell("Enter a port:");
    port = $string_utils:trim($command_utils:read());
  endwhile
  port = toint(port);
  try
    out = open_network_connection(host, port);
    player:tell("Successfully connected to ", host, ":", port, ".");
    `boot_player(out) ! ANY';
  except e (ANY)
    player:tell("Couldn't connect to ", host, ":", port, " (", e[2], "). Setup aborted.");
  endtry
  try
    this.host = host;
    this.port = port;
  except e (ANY)
    player:tell("Error setting host and port: ", e[2]);
  endtry
  player:tell("I need your client ID and client secret. Both of these values can be found in Grapevine Settings -> Games -> (click your game). Both secrets and IDs take the form of: 123e4567-e89b-12d3-a456-426655440000");
  player:tell("Client ID:");
  id = $command_utils:read();
  while (length(id) != 36)
    player:tell("Your client ID must be 36 characters in length.");
    player:tell("Client ID:");
    id = $command_utils:read();
  endwhile
  this.client_id = id;
  player:tell("Client ID set.");
  player:tell("Client secret:");
  secret = $command_utils:read();
  while (length(secret) != 36)
    player:tell("Your client secret must be 36 characters in length.");
    player:tell("Client secret:");
    secret = $command_utils:read();
  endwhile
  this.client_secret = secret;
  player:tell("Client secret set.");
  this.announce_player_connections = $command_utils:yes_or_no("Would you like player connections and disconnections to be announced?") == 1;
  player:tell("Setup is complete! You should now take the following steps:");
  player:tell("  1.) Modify #0:user_connected, #0:user_disconnected, and #0:server_started to call their equivalents on the bridge object. If you don't want to announce player connections and disconnections, remove \"players\" from the supports property and do not modify the verb counterparts.");
  player:tell("  2.) Modify ", this, ":local_announce to send local announcements somewhere applicable for your game.");
  player:tell("  3.) Modify your channel system (if any) to send messages using something like: $grapevine:send_event(\"channels/send\", [\"channel\" ->channel.name, \"name\" -> player.name, \"message\" ->\"This is a message! You should probably replace it with something meaningful.\"]);");
  player:tell("  4.) Enjoy! Report bugs or issues via the MOO channel on the Grapevine network, or to Sinistral on ChatMUD.");
else
  player:tell("Aborted.");
endif
.
;;player:tell("To continue setup, you must type `continue'. If you wish to complete setup later, you can type `abort' and call :initial_setup() on this object once you're ready."); while ((ind = read(player) in {"continue", "abort"}) == 0) endwhile if (ind == 1) mgnb = player:my_match_object("mgnb"); if  (valid(mgnb)) mgnb:initial_setup(); else player:tell("I couldn't find the Grapevine bridge object for setup. Please start setup manually."); endif else player:tell("Aborted."); endif player:tell("Setup complete!");
