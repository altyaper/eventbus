// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

import {Socket} from "phoenix"

let socket = new Socket("/socket")
socket.connect()

// Join a topic ("changologs.logs", "my-app.events", ...) and subscribe to
// everything published to it.
let channel = socket.channel("topic:changologs.logs", {})
channel.join()
  .receive("ok", resp => { console.log("Joined successfully", resp) })
  .receive("error", resp => { console.log("Unable to join", resp) })

channel.on("event", event => console.log("event", event))

// Publish from the client itself, over the same socket.
channel.push("publish", {hello: "world"})

export default socket
