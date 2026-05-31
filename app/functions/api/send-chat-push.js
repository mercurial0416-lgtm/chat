export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: corsHeaders(),
  });
}

export async function onRequestPost(context) {
  try {
    const body = await context.request.text();

    const res = await fetch("https://nwenbkthlpzlpfklgonb.supabase.co/functions/v1/send-chat-push", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": "eyJhbGciOiJIUzI1NiIsInJlZiI6Im53ZW5ia3RobHB6bHBma2xnb25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxMTA5MjMsImV4cCI6MjA5NTY4NjkyM30.PHojgVx7Yn1lUl88w_FtiMRwHBdLmVxkcUNBUBJILMU",
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInJlZiI6Im53ZW5ia3RobHB6bHBma2xnb25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxMTA5MjMsImV4cCI6MjA5NTY4NjkyM30.PHojgVx7Yn1lUl88w_FtiMRwHBdLmVxkcUNBUBJILMU",
      },
      body,
    });

    const text = await res.text();

    return new Response(text, {
      status: res.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": "application/json",
      },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: err?.message || "cloudflare proxy failed",
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders(),
          "Content-Type": "application/json",
        },
      }
    );
  }
}

export async function onRequestGet() {
  return new Response(
    JSON.stringify({
      ok: true,
      message: "send-chat-push proxy alive",
    }),
    {
      status: 200,
      headers: {
        ...corsHeaders(),
        "Content-Type": "application/json",
      },
    }
  );
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
  };
}
