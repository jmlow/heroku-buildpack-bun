const server = Bun.serve({
  port: process.env.PORT || 3000,
  fetch(req) {
    return new Response("Hello from bun-1.2!");
  },
});

console.log(`Bun server listening on port ${server.port}`);
