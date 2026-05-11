import type { VercelRequest, VercelResponse } from "@vercel/node";
import { streamText, stepCountIs } from "ai";
import { gateway } from "ai";
import { ChatRequestSchema } from "../lib/types";
import { buildSystemPrompt } from "../lib/prompt";
import { coachTools } from "../lib/tools";

export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const authHeader = req.headers.authorization;
  const expectedToken = process.env.COACH_API_TOKEN;
  if (expectedToken && authHeader !== `Bearer ${expectedToken}`) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  const parsed = ChatRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid request", details: parsed.error.flatten() });
    return;
  }

  const { messages, currentTime, context, starterContext, availabilityContext } = parsed.data;
  console.log("\n--- INCOMING REQUEST ---");
  console.log("currentTime:", currentTime);
  console.log("context:", JSON.stringify(context, null, 2));
  console.log("--- END REQUEST ---\n");
  const systemPrompt = buildSystemPrompt(currentTime, context, starterContext, availabilityContext);

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });

  try {
    const result = streamText({
      model: gateway("google/gemini-3-flash"),
      system: systemPrompt,
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
      tools: coachTools,
      stopWhen: stepCountIs(2),
      maxOutputTokens: 1024,
    });

    for await (const part of result.fullStream) {
      switch (part.type) {
        case "text-delta":
          res.write(`data: ${JSON.stringify({ text: part.text })}\n\n`);
          break;
        case "tool-call":
          res.write(
            `data: ${JSON.stringify({
              action: {
                toolName: part.toolName,
                params: part.input,
              },
            })}\n\n`
          );
          break;
      }
    }

    res.write("data: [DONE]\n\n");
    res.end();
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Internal server error";
    res.write(`data: ${JSON.stringify({ error: message })}\n\n`);
    res.end();
  }
}
