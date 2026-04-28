import { generateModels } from "https://cdn.jsdelivr.net/npm/wow-model-viewer@1.5.3/index.js";

function setStatus(status, detail = "") {
  window.__renderStatus = detail ? `${status}: ${detail}` : status;
  const banner = document.getElementById("debugBanner");
  const overlay = document.getElementById("overlayStatus");
  if (banner) banner.textContent = `status: ${window.__renderStatus}`;
  if (overlay) overlay.textContent = `status: ${window.__renderStatus}`;
}

async function run() {
  try {
    setStatus("initializing");
    const params = new URLSearchParams(window.location.search);
    const scenario = params.get("scenario") || "tauren";
    const env = params.get("env") || "live";

    const taurenCharacter = {
      race: 6,
      gender: 1,
      noCharCustomization: true,
      items: [
        [21, 20379],
        [22, 28787]
      ]
    };

    const gnomeSampleCharacter = {
      race: 7,
      gender: 1,
      skin: 4,
      face: 0,
      hairStyle: 5,
      hairColor: 5,
      facialStyle: 5,
      items: [
        [1, 1170], [3, 4925], [5, 9575], [6, 25235], [7, 2311], [8, 21154], [9, 14618], [10, 9534], [15, 17238], [21, 20379], [22, 28787]
      ]
    };

    const gnomeNoItemsCharacter = {
      race: 7,
      gender: 1,
      skin: 4,
      face: 0,
      hairStyle: 5,
      hairColor: 5,
      facialStyle: 5,
      items: []
    };

    const dracthyrDemoCharacter = {
      race: 45,
      gender: 0,
      skin: 1,
      primaryColor: 1,
      face: 0,
      ears: 1,
      items: [[1, 1170], [3, 4925], [5, 9575], [6, 25235], [7, 2311], [8, 21154], [9, 14618], [10, 9534], [15, 17238], [21, 20379], [22, 28787]]
    };

    const character = scenario === "gnome-sample"
      ? gnomeSampleCharacter
      : scenario === "gnome-no-items"
        ? gnomeNoItemsCharacter
        : scenario === "dracthyr-demo"
          ? dracthyrDemoCharacter
          : taurenCharacter;

    setStatus("generating-model");
    const model = await generateModels(1.25, "#model_3d", character, env);
    window.__model = model;
    setStatus("model-created", `${scenario}/${env}`);

    const canvas = document.querySelector("canvas");
    if (canvas) {
      canvas.addEventListener("webglcontextlost", () => {
        setStatus("webgl-context-lost");
      });
      canvas.addEventListener("webglcontextrestored", () => {
        setStatus("webgl-context-restored");
      });
    }

    setStatus("waiting-for-frames");
    setTimeout(() => {
      window.__renderReady = true;
      setStatus("ready");
    }, 8000);
  } catch (error) {
    window.__renderError = error?.message || String(error);
    setStatus("error", window.__renderError);
  }
}

run();
