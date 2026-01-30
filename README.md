# Stationeers PauseBot

Automatically pause a Stationeers dedicated server on startup by briefly connecting a fake client and disconnecting, triggering the built-in `AutoPauseServer` feature. No dependencies beyond Python 3.6+.

## Usage

```bash
# Auto-detects version from server log, no password
LOG_FILE=/path/to/server.log python3 fake-connect.py

# With password
LOG_FILE=/path/to/server.log python3 fake-connect.py "mypassword"

# With password and explicit version (skips log detection)
python3 fake-connect.py "mypassword" "0.2.6136.26812"
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/home/steam/stationeers/logs/server.log` | **Set this** to your server's log file path. The script reads it to auto-detect the game version. The default assumes a SteamCMD install under `/home/steam/` — your path will differ depending on your setup. |
| `GAME_PORT` | `27016` | Server game port |
| `SERVER_PASSWORD` | (empty) | Server password |

CLI arguments override environment variables for password and version.

### Requirements

- Python 3.6+ (stdlib only, no pip dependencies)
- Stationeers dedicated server with `AutoPauseServer` enabled
- Run on the same machine as the server (connects to 127.0.0.1)

Make sure `AutoPauseServer` is enabled in your world's `setting.xml`:

```xml
<AutoPauseServer>true</AutoPauseServer>
```

### systemd Integration

The included `startup-pause.sh` script is designed to run as a systemd `ExecStartPost` command. It waits for the server to be fully ready (watching for "registered with session" in the log), then runs `fake-connect.py`. You'll need to edit the paths in the script to match your server installation.

Example service snippet:

```ini
[Service]
# Clear old log so grep doesn't match stale entries
ExecStartPre=rm -f /path/to/stationeers/logs/server.log
ExecStart=/usr/bin/tmux new-session -d -s stationeers /path/to/start-server.sh
ExecStartPost=/path/to/startup-pause.sh
```

## The Problem

Stationeers has an `AutoPauseServer` setting that pauses game simulation when no players are connected. However, it only activates when the **last client disconnects** — not on startup with zero players. This means your server burns CPU simulating an empty world until someone joins.

On Linux, the dedicated server runs with `-batchmode -nographics` and **does not read stdin**, so you can't send console commands like `pause true` via tmux or pipes. There's also no RCON support.

## How It Works

PauseBot solves this by speaking the server's network protocol directly:

1. Performs a RakNet UDP handshake (protocol version 6)
2. Receives a `VerifyPlayerRequest` challenge from the server
3. Sends a `VerifyPlayer` response with valid credentials
4. Stays connected long enough to receive join data (~10 seconds)
5. Disconnects cleanly, triggering `AutoPauseServer`

The server sees a normal player connect and disconnect, then pauses because no clients remain.

The protocol was reverse-engineered by decompiling `Assembly-CSharp.dll` from the game's managed DLLs. No Steam authentication is required — the server only validates the password and game version, not Steam tickets.

## Server Log Output

When PauseBot runs successfully, you'll see this in the server log:

```
Process verify player 76561197967126507
Client: PauseBot Connected. 670304 / 670304
Client has disconnected.
Client disconnected: <id> | PauseBot
No clients connected. Will save and pause in 10 seconds.
Server Paused
```

## Protocol Details

See [PROTOCOL.md](PROTOCOL.md) for detailed documentation of the Stationeers network protocol — useful if you're building other tools (RCON alternatives, server monitors, bots, etc.).

## License

MIT License. See [LICENSE](LICENSE).
