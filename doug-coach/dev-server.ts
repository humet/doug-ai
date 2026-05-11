import { createServer } from "node:http";
import { config } from "dotenv";
import handler from "./api/chat";

config();

const server = createServer(async (req, res) => {
  // CORS for local dev
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.url === "/api/chat" && req.method === "POST") {
    const chunks: Buffer[] = [];
    for await (const chunk of req) {
      chunks.push(chunk as Buffer);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString());

    // Adapt to VercelRequest shape
    const vercelReq = Object.assign(req, {
      body,
      query: {},
      cookies: {},
    });

    await handler(vercelReq as any, res as any);
    return;
  }

  res.writeHead(404);
  res.end("Not found");
});

const port = Number(process.env.PORT) || 3000;
server.listen(port, () => {
  console.log(`Coach API running at http://localhost:${port}/api/chat`);
});
