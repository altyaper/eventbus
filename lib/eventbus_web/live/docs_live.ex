defmodule EventbusWeb.DocsLive do
  @moduledoc """
  Public integration guide: how to publish over HTTP, listen from React
  (with the `@altyaper/eventbus-react` package) or plain JavaScript, and
  restrict listening with topic tokens.
  """

  use EventbusWeb, :live_view

  import EventbusWeb.AppComponents, only: [code_block: 1]

  @package "@altyaper/eventbus-react"

  @sections [
    overview: "How it works",
    setup: "Set up an application",
    publish: "Publish events",
    react: "Listen from React",
    javascript: "Plain JavaScript",
    private: "Private topics",
    rules: "Topics & origins"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Docs")
     |> assign(:sections, @sections)
     |> assign(:package, @package)}
  end

  # Snippets use the address the browser is on, like the app's quick start:
  # PHX_HOST may be a LAN IP while the page is viewed through a TLS proxy.
  @impl true
  def handle_params(_params, uri, socket) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(uri)
    http = URI.to_string(%URI{scheme: scheme, host: host, port: port})
    ws = URI.to_string(%URI{scheme: ws_scheme(scheme), host: host, port: port, path: "/socket"})

    {:noreply, assign(socket, :snippets, snippets(http, ws))}
  end

  defp ws_scheme("https"), do: "wss"
  defp ws_scheme(_scheme), do: "ws"

  defp snippets(http, ws) do
    %{
      curl: """
      curl -u "$CLIENT_ID:$CLIENT_SECRET" \\
        -X POST #{http}/api/topics/myapp.deploys/events \\
        -H "Content-Type: application/json" \\
        -d '{"message": "v1.4.0 is live"}'\
      """,
      envelope: """
      {
        "topic": "myapp.deploys",
        "payload": { "message": "v1.4.0 is live" },
        "published_at": "2026-10-03T12:00:00.000000Z"
      }\
      """,
      install: "npm install #{@package}",
      react: """
      import { EventbusProvider, useTopic } from "#{@package}";

      export function App() {
        return (
          <EventbusProvider url="#{ws}">
            <Deploys />
          </EventbusProvider>
        );
      }

      function Deploys() {
        const { status, error, events } = useTopic("myapp.deploys");

        if (status === "error") return <p>Can't listen: {error}</p>;
        return (
          <ul>
            {events.map((e) => (
              <li key={e.published_at}>{e.payload.message}</li>
            ))}
          </ul>
        );
      }\
      """,
      on_event: """
      useTopic("myapp.deploys", {
        keep: 0, // don't store events, just react to them
        onEvent: (event) => toast(event.payload.message),
      });\
      """,
      server: """
      import { createPublisher } from "#{@package}/server";

      const eventbus = createPublisher({
        url: "#{http}",
        clientId: process.env.EVENTBUS_CLIENT_ID,
        clientSecret: process.env.EVENTBUS_CLIENT_SECRET,
      });

      await eventbus.publish("myapp.deploys", { message: "v1.4.0 is live" });\
      """,
      javascript: """
      import { Socket } from "phoenix";

      const socket = new Socket("#{ws}");
      socket.connect();

      const channel = socket.channel("topic:myapp.deploys");
      channel.on("event", ({ topic, payload, published_at }) => {
        console.log(topic, payload, published_at);
      });
      channel
        .join()
        .receive("ok", () => console.log("listening"))
        .receive("error", ({ reason }) => console.error(reason));\
      """,
      mint: """
      curl -u "$CLIENT_ID:$CLIENT_SECRET" \\
        -X POST #{http}/api/tokens \\
        -H "Content-Type: application/json" \\
        -d '{"user_id": "u_123", "grants": ["myapp.user.u_123", "myapp.board.ab12.*"]}'\
      """,
      mint_response: """
      { "token": "SFMyNTY…", "expires_at": "2026-10-03T12:15:00.000000Z" }\
      """,
      private_join: """
      // `token` comes from your backend, which got it from POST /api/tokens.
      // Params are a function so a rejoin after a reconnect sends the latest one.
      const channel = socket.channel("topic:myapp.board.ab12", () => ({ token }));
      channel.on("event", (event) => render(event));
      channel.on("revoked", () => channel.leave());
      channel.join().receive("error", async ({ reason }) => {
        if (reason === "token expired" || reason === "token revoked") {
          token = await fetchTokenFromYourBackend(); // the automatic rejoin uses it
        }
      });\
      """,
      revoke: """
      # Close u_123's channels on one board (their token stays valid until it expires)
      curl -u "$CLIENT_ID:$CLIENT_SECRET" -X POST #{http}/api/tokens/revoke \\
        -H "Content-Type: application/json" -d '{"user_id": "u_123", "grants": ["myapp.board.ab12.*"]}'

      # Close all of u_123's channels and refuse every token minted before now
      curl -u "$CLIENT_ID:$CLIENT_SECRET" -X POST #{http}/api/tokens/revoke \\
        -H "Content-Type: application/json" -d '{"user_id": "u_123"}'\
      """
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:docs}>
      <section id="docs-hero" class="mb-10 sm:mb-12">
        <span class="inline-flex items-center gap-2 rounded-full border border-base-content/10 bg-base-100/60 px-3 py-1 text-xs font-medium text-base-content/70">
          <.icon name="hero-book-open-micro" class="size-4 text-primary" /> Integration guide
        </span>
        <h1 class="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">Docs</h1>
        <p class="mt-2 max-w-xl text-base-content/60">
          Publish events from your backend over HTTP and receive them live in the browser over
          WebSockets. The React package does the WebSocket part for you.
        </p>
      </section>

      <div class="grid gap-10 lg:grid-cols-[13rem_minmax(0,1fr)]">
        <nav id="docs-toc" aria-label="On this page" class="hidden lg:block">
          <ul class="sticky top-24 space-y-0.5 border-l border-base-content/10 text-sm">
            <li :for={{id, title} <- @sections}>
              <a
                href={"##{id}"}
                class="-ml-px block border-l border-transparent py-1.5 pl-4 text-base-content/60 transition-colors hover:border-primary hover:text-base-content"
              >
                {title}
              </a>
            </li>
          </ul>
        </nav>

        <article class="min-w-0 space-y-14">
          <.doc_section id="overview" title="How it works">
            <ol class="grid gap-3 sm:grid-cols-3">
              <.step n={1} icon="hero-squares-2x2" title="Applications own topics">
                An application named <code class="font-mono">myapp</code> owns every topic
                named <code class="font-mono">myapp.*</code>.
              </.step>
              <.step n={2} icon="hero-paper-airplane" title="Publish over HTTP">
                Your backend POSTs JSON to a topic with the application's client ID and secret.
              </.step>
              <.step n={3} icon="hero-signal" title="Listen over WebSockets">
                Browsers join the topic and get every event the moment it's published.
              </.step>
            </ol>
            <p>
              Events are delivered live and not stored: a listener only receives what is
              published while it's connected.
            </p>
          </.doc_section>

          <.doc_section id="setup" title="Set up an application">
            <ol class="list-decimal space-y-2 pl-5 marker:font-semibold marker:text-primary">
              <li>
                Under <.link navigate={~p"/apps"} class="font-medium text-primary hover:underline">My Apps</.link>,
                create an application. Its name becomes the prefix of its topics. Confirm
                your email first; until then you have a sandbox app with up to 5 topics.
              </li>
              <li>
                Copy the <strong>client ID</strong>
                and <strong>secret</strong>
                from its Credentials page. The secret is shown once; regenerate it if you lose it.
              </li>
              <li>
                On its Origins page, add every site that will listen from a browser, e.g. <code class="font-mono">https://myapp.example.com</code>. Wildcard subdomains
                like <code class="font-mono">https://*.example.com</code> work too.
              </li>
            </ol>
          </.doc_section>

          <.doc_section id="publish" title="Publish events">
            <p>
              POST a JSON object to <code class="font-mono">/api/topics/&lt;topic&gt;/events</code>
              with HTTP Basic auth: the client ID as user, the secret as password.
            </p>
            <.code_block id="snippet-curl" caption="shell" code={@snippets.curl} />
            <p>
              The server answers <code class="font-mono">202 Accepted</code>
              with the event exactly as listeners receive it:
            </p>
            <.code_block id="snippet-envelope" caption="response" code={@snippets.envelope} />
            <div class="overflow-hidden rounded-xl border border-base-content/10">
              <table id="publish-errors" class="w-full text-left text-sm">
                <thead class="bg-base-content/5 text-xs uppercase tracking-wide text-base-content/50">
                  <tr>
                    <th class="px-4 py-2 font-medium">Status</th>
                    <th class="px-4 py-2 font-medium">Meaning</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/10">
                  <tr :for={{status, meaning} <- publish_errors()}>
                    <td class="px-4 py-2 font-mono text-xs">{status}</td>
                    <td class="px-4 py-2 text-base-content/70">{meaning}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.doc_section>

          <.doc_section id="react" title="Listen from React">
            <p>
              <code class="font-mono">{@package}</code>
              opens one WebSocket for your app, joins topics as components need them, and
              rejoins by itself after a dropped connection.
            </p>
            <.code_block id="snippet-install" caption="shell" code={@snippets.install} />
            <.code_block id="snippet-react" caption="App.jsx" code={@snippets.react} />
            <p>
              <code class="font-mono">useTopic</code>
              returns <code class="font-mono">status</code>
              (<code class="font-mono">joining</code>, <code class="font-mono">joined</code>
              or <code class="font-mono">error</code>), <code class="font-mono">error</code>
              (why the join was refused), <code class="font-mono">events</code>
              (the last 50, oldest first), <code class="font-mono">lastEvent</code>
              and <code class="font-mono">clear</code>. Any number of components can listen
              to the same topic; they share one channel. To react to events instead of
              rendering a list:
            </p>
            <.code_block id="snippet-on-event" caption="Notifications.jsx" code={@snippets.on_event} />

            <h3 class="pt-2 font-semibold text-base-content">Publishing from your server</h3>
            <p>
              The package also has a publisher for Node, edge functions and route handlers.
              Failures throw an <code class="font-mono">EventbusPublishError</code>
              with the HTTP <code class="font-mono">status</code>.
            </p>
            <.code_block id="snippet-server" caption="server.js" code={@snippets.server} />
            <p class="flex gap-2 rounded-xl bg-warning/10 p-3 text-sm ring-1 ring-warning/30">
              <.icon
                name="hero-exclamation-triangle-micro"
                class="mt-0.5 size-4 shrink-0 text-warning"
              />
              <span>
                Never import <code class="font-mono">{@package}/server</code>
                in browser code: the secret would ship to every visitor.
              </span>
            </p>
          </.doc_section>

          <.doc_section id="javascript" title="Plain JavaScript">
            <p>
              Not using React? Any Phoenix Channels client works. Join
              <code class="font-mono">topic:&lt;topic&gt;</code>
              on the <code class="font-mono">/socket</code>
              WebSocket and listen for <code class="font-mono">event</code>.
            </p>
            <.code_block id="snippet-javascript" caption="listen.js" code={@snippets.javascript} />
          </.doc_section>

          <.doc_section id="private" title="Private topics">
            <p>
              Anyone who knows a topic's name can listen to it, from an allowed origin or
              from outside a browser. To decide who listens, your backend mints a
              short-lived token listing the topics its user may join. Entries are exact
              topic names or <code class="font-mono">name.*</code>
              patterns, which match every topic below the name. All must start with
              your application's name.
            </p>
            <.code_block id="snippet-mint" caption="shell" code={@snippets.mint} />
            <.code_block id="snippet-mint-response" caption="response" code={@snippets.mint_response} />
            <p>
              Tokens last 15 minutes unless you pass <code class="font-mono">ttl</code>
              (seconds, at most 3600). The browser passes the token when it joins:
            </p>
            <.code_block id="snippet-private-join" caption="listen.js" code={@snippets.private_join} />
            <p>
              Turn on <strong>Require tokens to listen</strong>
              in the application's settings to refuse listeners without a token. Until
              then tokens are checked when present and anonymous listeners still get in.
              When a user loses access, revoke it:
            </p>
            <.code_block id="snippet-revoke" caption="shell" code={@snippets.revoke} />
            <p>
              Join errors: <code class="font-mono">unauthorized</code>
              (token required, none sent), <code class="font-mono">forbidden</code>
              (the token doesn't grant this topic), <code class="font-mono">token expired</code>,
              <code class="font-mono">token revoked</code>
              and <code class="font-mono">invalid token</code>.
            </p>
          </.doc_section>

          <.doc_section id="rules" title="Topics & origins">
            <ul class="list-disc space-y-2 pl-5 marker:text-base-content/30">
              <li>
                Topic names use lowercase letters, digits, <code class="font-mono">.</code>
                <code class="font-mono">-</code>
                and <code class="font-mono">_</code>, and start and end with a letter or digit.
              </li>
              <li>
                An application can only publish to topics named after it. A topic appears in
                its list the first time something is published to it.
              </li>
              <li>
                A page whose origin was added to an application can only listen to that
                application's topics. Other topics refuse the join with <code class="font-mono">origin not allowed</code>.
              </li>
              <li>
                Origins set by the server's administrator (<code class="font-mono">PHX_HOST</code>, <code class="font-mono">PHX_EXTRA_ORIGINS</code>) can listen to every topic.
              </li>
            </ul>
          </.doc_section>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp publish_errors do
    [
      {"401", "Missing or wrong client ID or secret."},
      {"403", "The topic belongs to another application."},
      {"422", "Invalid topic name."}
    ]
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp doc_section(assigns) do
    ~H"""
    <section id={@id} class="scroll-mt-24">
      <h2 class="group flex items-center gap-2 text-xl font-semibold tracking-tight">
        <a href={"##{@id}"} class="hover:text-primary">{@title}</a>
        <.icon
          name="hero-link-micro"
          class="size-4 text-base-content/30 opacity-0 transition-opacity group-hover:opacity-100"
        />
      </h2>
      <div class="mt-4 space-y-4 leading-relaxed text-base-content/70">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :n, :integer, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp step(assigns) do
    ~H"""
    <li class="rounded-2xl border border-base-content/10 bg-base-100 p-4 shadow-sm transition-all duration-300 hover:-translate-y-0.5 hover:shadow-md">
      <div class="flex items-center gap-2">
        <span class="grid size-8 place-items-center rounded-lg bg-primary/10 text-primary">
          <.icon name={@icon} class="size-4" />
        </span>
        <span class="text-xs font-semibold text-base-content/40">0{@n}</span>
      </div>
      <p class="mt-3 font-semibold text-base-content">{@title}</p>
      <p class="mt-1 text-sm text-base-content/60">{render_slot(@inner_block)}</p>
    </li>
    """
  end
end
