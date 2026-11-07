// <define:__ROUTES__>
var define_ROUTES_default = {
  version: 1,
  include: ["/politica-de-privacidade", "/termos-e-condicoes"],
  exclude: []
};

// ../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/pages-dev-pipeline.ts
import worker from "/Users/viniciushorta/Documents/Projetos/escola-em-dia/ui/website/.wrangler/tmp/pages-L0SMKr/functionsWorker-0.34444878219409847.mjs";
import { isRoutingRuleMatch } from "/Users/viniciushorta/.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/pages-dev-util.ts";
export * from "/Users/viniciushorta/Documents/Projetos/escola-em-dia/ui/website/.wrangler/tmp/pages-L0SMKr/functionsWorker-0.34444878219409847.mjs";
var routes = define_ROUTES_default;
var pages_dev_pipeline_default = {
  fetch(request, env, context) {
    const { pathname } = new URL(request.url);
    for (const exclude of routes.exclude) {
      if (isRoutingRuleMatch(pathname, exclude)) {
        return env.ASSETS.fetch(request);
      }
    }
    for (const include of routes.include) {
      if (isRoutingRuleMatch(pathname, include)) {
        const workerAsHandler = worker;
        if (workerAsHandler.fetch === void 0) {
          throw new TypeError("Entry point missing `fetch` handler");
        }
        return workerAsHandler.fetch(request, env, context);
      }
    }
    return env.ASSETS.fetch(request);
  }
};
export {
  pages_dev_pipeline_default as default
};
//# sourceMappingURL=9dpzz4h63yn.js.map
