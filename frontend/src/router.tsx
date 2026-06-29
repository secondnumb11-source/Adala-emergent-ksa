import { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { routeTree } from "./routeTree.gen";

export const getRouter = () => {
  const queryClient = new QueryClient();

  const router = createRouter({
    routeTree,
    context: { queryClient },
    scrollRestoration: true,
    defaultPreloadStaleTime: 0,
    // Prefetch route chunks/data when a link enters the viewport (on idle in
    // practice, since TanStack uses requestIdleCallback for viewport prefetch).
    // Keeps initial bundle small while making navigation feel instant.
    defaultPreload: "viewport",
    defaultPreloadDelay: 50,
  });

  return router;
};
