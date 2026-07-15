// ============================================================
// Edge Function: reporte-ia
// Llama a OpenAI con la API key ESCONDIDA en el servidor.
// La app le manda los datos de la sesión; aquí se arma el prompt,
// se llama a OpenAI y se devuelve el reporte. La key nunca sale de aquí.
// ============================================================

// Estudios científicos (verificados). La IA los cita en el reporte.
const ESTUDIOS = `
ESTUDIOS CIENTÍFICOS DISPONIBLES PARA CITAR (usa cita APA: Autor et al., año):

1. Serafim et al. (2023) - "Which resistance training is safest to practice? A systematic review" (Journal of Orthopaedic Surgery and Research). Hallazgo: revisión sistemática sobre seguridad en el entrenamiento de fuerza; identifica que la técnica incorrecta y la sobrecarga son factores de riesgo principales de lesión musculoesquelética.

2. Chae et al. (2023) - "An artificial intelligence exercise coaching mobile app: RCT in posture correction" (Interactive Journal of Medical Research). Hallazgo: una app móvil de IA para corregir la postura demostró, en un ensayo controlado aleatorizado, mejoras significativas en la corrección postural.

3. Ko et al. (2024) - "Pose estimation for exercise analysis" (IEEE Access). Hallazgo: los sistemas de estimación de pose permiten analizar la ejecución de ejercicios y detectar errores de técnica en tiempo real con buena precisión.

4. Liew et al. (2025) - "Human pose estimation for exercise monitoring" (IJACSA). Hallazgo: el monitoreo de ejercicios mediante estimación de pose humana es viable en dispositivos móviles y da retroalimentación inmediata sobre la forma del movimiento.

5. Supanich et al. (2023) - "Real-time body movement detection" (ICACCS, IEEE). Hallazgo: la detección de movimiento corporal en tiempo real mediante puntos clave del cuerpo permite cuantificar ángulos articulares y evaluar la calidad del movimiento.
`;

Deno.serve(async (req) => {
  // Permitir que la app (de otro origen) llame a esta función
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    // La API key vive en los secrets de Supabase, NO en la app
    const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_KEY) {
      return new Response(JSON.stringify({ error: "Falta OPENAI_API_KEY" }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
    }

    // Datos que manda la app
    const body = await req.json();
    const ejercicio = body.ejercicio ?? "ejercicio";
    const errores: string[] = body.errores ?? [];
    const totalReps = body.totalReps ?? 0;
    const validReps = body.validReps ?? 0;
    const invalidReps = body.invalidReps ?? 0;
    const userLevel = body.userLevel ?? "Principiante";
    const userWeightKg = body.userWeightKg ?? 70;

    const systemPrompt = `
Actúa como un médico especialista en medicina deportiva y biomecánica, redactando
un informe profesional para un usuario de una app de entrenamiento.

DATOS DE LA SESIÓN:
- Ejercicio: "${ejercicio}"
- Usuario: nivel ${userLevel}, ${userWeightKg}kg
- Repeticiones totales: ${totalReps}
- Repeticiones correctas: ${validReps}
- Repeticiones con error: ${invalidReps}
- Errores detectados: ${errores.length === 0 ? "Ninguno, técnica correcta" : errores.join(", ")}.

${ESTUDIOS}

INSTRUCCIONES:
Redacta un informe profesional y con tacto, en español, nivel académico pero claro.
Donde corresponda, CITA los estudios científicos de arriba en formato APA (ejemplo:
"Serafim et al. (2023) señala que..."). Usa al menos 3 de los estudios en la sección
de evidencia científica, relacionándolos con los errores del usuario o con la
importancia de la buena técnica. NO inventes estudios distintos a los listados.

RESPONDE SOLO con un JSON válido sin texto extra:
{
  "resumen_general": "2-3 oraciones resumiendo el desempeño de la sesión",
  "analisis_biomecanico": "4-6 oraciones explicando qué pasó con el cuerpo durante el ejercicio y los errores",
  "musculos_en_riesgo": "nombre de los músculos o articulaciones en riesgo",
  "posible_lesion": "nombre de la lesión específica que podría desarrollarse",
  "evidencia_cientifica": "5-8 oraciones citando al menos 3 estudios (formato APA)",
  "recomendaciones": "4-6 oraciones con un plan de corrección práctico",
  "nivel_riesgo": "bajo" | "medio" | "alto"
}
`;

    const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENAI_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        max_tokens: 1200,
        temperature: 0.4,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: "Genera el informe completo de la sesión." },
        ],
      }),
    });

    if (!openaiRes.ok) {
      const errText = await openaiRes.text();
      return new Response(JSON.stringify({ error: "OpenAI error", detail: errText }),
        { status: 502, headers: { ...cors, "Content-Type": "application/json" } });
    }

    const data = await openaiRes.json();
    const content: string = data.choices[0].message.content;
    const clean = content.replace(/```json|```/g, "").trim();

    // Devolvemos el JSON ya limpio para que la app lo use directo
    return new Response(clean, {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } });
  }
});