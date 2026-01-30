# Stationeers Network Protocol Notes

Technical details of the Stationeers dedicated server network protocol, reverse-engineered by decompiling `Assembly-CSharp.dll` from the game's managed DLLs using [ILSpy](https://github.com/icsharpcode/ILSpy).

These notes may be useful for anyone building Stationeers networking tools (RCON alternatives, server monitors, bots, etc.).

## Transport Layer: RakNet

Stationeers uses RakNet over UDP with protocol version 6.

### Handshake Sequence

1. **Client → Server:** `OpenConnectionRequest1` (0x05) — includes RakNet magic bytes and MTU padding
2. **Server → Client:** `OpenConnectionReply1` (0x06) — returns negotiated MTU
3. **Client → Server:** `OpenConnectionRequest2` (0x07) — includes client GUID
4. **Server → Client:** `OpenConnectionReply2` (0x08) — connection established
5. **Client → Server:** `ConnectionRequest` (0x09) — in a reliable frame
6. **Server → Client:** `ConnectionRequestAccepted` (0x10) — in a reliable frame
7. **Client → Server:** `NewIncomingConnection` (0x13) — in a reliable frame

After step 7, the RakNet connection is established and game-level messages begin.

### RakNet Magic Bytes

```
00 FF FF 00 FE FE FE FE FD FD FD FD 12 34 56 78
```

### Reliable Frame Format (0x84)

```
[0x84]                          -- frame type
[sequence: 3 bytes LE]          -- frame sequence number
[reliability: 1 byte]           -- 0x60 = reliable ordered
[bit_length: 2 bytes BE]        -- payload length in bits
[reliable_msg_num: 3 bytes LE]  -- reliable message number
[ordered_msg_num: 3 bytes LE]   -- ordered message number
[ordering_channel: 1 byte]      -- 0 for general traffic
[payload: N bytes]              -- the actual message data
```

### ACK Format (0xC0)

```
[0xC0]                          -- ACK type
[count: 2 bytes BE]             -- number of ranges (1)
[single_range: 1 byte]          -- 1 = single sequence number
[sequence: 3 bytes LE]          -- sequence number being ACKed
```

## Application Layer: Stationeers Messages

### Message Structure

All game messages are prefixed with a channel byte and message type byte:

```
[channel: 1 byte] [message_type: 1 byte] [payload...]
```

### Network Channels

| Channel | Value | Description |
|---------|-------|-------------|
| `GeneralTraffic` | `0x86` (134) | Used for all game messages including auth |

### Message Types (MessageFactory Index)

| Type | Value | Direction | Description |
|------|-------|-----------|-------------|
| `VerifyPlayer` | `0x70` (112) | Client → Server | Auth response with credentials |
| `VerifyPlayerRequest` | `0x71` (113) | Server → Client | Auth challenge |

### Connection Methods

| Method | Value | Description |
|--------|-------|-------------|
| `RocketNet` | `0` | Direct UDP (used by dedicated servers) |
| `FacepunchSteamP2P` | `1` | Steam P2P networking |
| `None` | `2` | Not connected |

### String Encoding

Stationeers uses a custom binary format for strings (via `RocketBinaryWriter`), **not** the .NET 7-bit encoded integer format:

```
[length: int32 LE]  -- number of UTF-8 bytes (-1 for null)
[data: N bytes]     -- UTF-8 encoded string
```

## Authentication Flow

### VerifyPlayerRequest (Server → Client)

Sent immediately after the RakNet handshake completes:

```
[channel: 0x86]
[msg_type: 0x71]
[OwnerConnectionId: int64 LE]     -- server's host ID (-1 for dedicated)
[ClientConnectionId: int64 LE]    -- RakNet GUID assigned to this client
[PasswordRequired: bool (1 byte)]
[ConnectionMethod: byte]
```

### VerifyPlayer (Client → Server)

Client responds with credentials:

```
[channel: 0x86]
[msg_type: 0x70]
[OwnerConnectionId: int64 LE]     -- MUST be ClientConnectionId from request
[ClientId: uint64 LE]             -- Steam ID (not validated by server)
[Name: string]                    -- Player display name
[Password: string]                -- Server password
[Version: string]                 -- Game version (e.g. "0.2.6136.26812")
[ConnectionMethod: byte]          -- 0 for RocketNet
```

### Server Validation (VerifyConnection)

The server checks the following, in order:

1. **Blacklist** — is the ClientId banned?
2. **Password** — does it match the server password? (skipped if server has no password)
3. **Version** — does it match the server's game version?

The server does **not** validate Steam authentication tickets. Any ClientId is accepted as long as it passes the above checks.

### OwnerConnectionId: The Critical Detail

The `OwnerConnectionId` field in `VerifyPlayer` is stored as the client's `connectionId` in the server's client list. When a player disconnects, the server calls `Client.Find(connectionId)` using the RakNet GUID to locate and remove the client object.

If `OwnerConnectionId` doesn't match the actual RakNet GUID (which the server sends as `ClientConnectionId` in the challenge), `Client.Find()` fails, the client is never properly removed, and features like `AutoPauseServer` won't trigger.

## Join Data Flow

After successful authentication:

1. Server adds client to `ProcessJoinQueue`
2. Server **pauses the game** to serialize world state
3. Server sends serialized world data as join data (~670KB for a typical world)
4. Client must ACK all RakNet frames during transfer
5. Server marks client as `Connected` when all data is sent
6. Server **unpauses the game**

The client must stay connected and ACK frames throughout this process, otherwise the server logs errors about failed join data delivery.
