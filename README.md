# MOOVine

This is a Stunt-compatible Grapevine interface, designed to allow MOOs to connect and interact on the Grapevine network.

[Source Code](https://git.chatmud.com/distantorigin/moovine/raw/master/grapevine.moo?inline=false]

## Requirements

- A TCP-to-websocket bridge, such as [Websocat](https://www.github.com/vi/websocat).
- At minimum, a MOO server running [LambdaMOO-Stunt v10](https://github.com/toddsundsted/stunt).
- A client ID and secret from the [Grapevine](https://www.grapevine.haus/) website.

## What is Grapevine?

Grapevine is an inter-MUD chat network, acting as a communication bridge between worlds as well as a web-based directory of games. It is [open source](https://github.com/oestrich/grapevine) and the specification can be [viewed here](https://grapevine.haus/docs).

## Installation

To connect to the Grapevine network, you will require a TCP-websocket bridge. My personal favorite is Websocat, which offers the convenience and peace of mind of TLS connections and much more. This guide will assume you are using Websocat and a basic flavor of Linux. Windows Subsystem for Linux and macOS will likely work similarly, though haven't been tested extensively.

### Installing and Running Websocat

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
cargo install websocat --features=ssl
nohup websocat tcp-l:127.0.0.1:8081 wss://grapevine.haus/socket -v &
```

**Note**: You should replace 8081 with your port number of choice.

### Installing MOOVine

Paste the contents of [grapevine.moo](https://git.chatmud.com/distantorigin/moovine/raw/master/grapevine.moo?inline=false) into your MOO and follow the setup instructions. you are responsible for integrating MOOVine into your channel system of choice. IF you suspect that something has gone awry, are having connectivity issues, or unexpected behavior occurs, add yourself to the .debuggers list on the newly created object to receive information about what's going on.

## Support

All out-of-box MOOVine objects will be automatically subscribed to the MOO channel on Grapevine. This is a channel for discussion of its namesake, and is a universally accepted place to ask questions about MOOVine. If you are unable to speak on the channel, connect to [ChatMUD](https://grapevine.haus/games/ChatMUD/play) at chatmud.com port 7777 and ask your question on the dev channel.

## Change Log
### Version 1.0 (11/20/2019)

- Initial release.