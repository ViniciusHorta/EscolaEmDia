import { onRequest as __politica_de_privacidade_js_onRequest } from "/Users/viniciushorta/Documents/Projetos/escola-em-dia/ui/website/functions/politica-de-privacidade.js"
import { onRequest as __termos_e_condicoes_js_onRequest } from "/Users/viniciushorta/Documents/Projetos/escola-em-dia/ui/website/functions/termos-e-condicoes.js"

export const routes = [
    {
      routePath: "/politica-de-privacidade",
      mountPath: "/",
      method: "",
      middlewares: [],
      modules: [__politica_de_privacidade_js_onRequest],
    },
  {
      routePath: "/termos-e-condicoes",
      mountPath: "/",
      method: "",
      middlewares: [],
      modules: [__termos_e_condicoes_js_onRequest],
    },
  ]