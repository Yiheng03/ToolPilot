import { lazy, Suspense } from "react"
import type { ComponentType } from "react"

export default function dynamic<TProps extends object>(
  loader: () => Promise<ComponentType<TProps> | { default: ComponentType<TProps> }>,
  _options?: unknown,
) {
  const LazyComponent = lazy(async () => {
    const loaded = await loader()
    if (typeof loaded === "function") {
      return { default: loaded }
    }
    return loaded
  })

  return function DynamicComponent(props: TProps) {
    return (
      <Suspense fallback={null}>
        <LazyComponent {...props} />
      </Suspense>
    )
  }
}
