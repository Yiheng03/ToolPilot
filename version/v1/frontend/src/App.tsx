import HomePage from "@/pages/HomePage"
import KnowledgePage from "@/pages/KnowledgePage"
import MarketPage from "@/pages/MarketPage"

export default function App() {
  const path = window.location.pathname

  if (path.startsWith("/market")) {
    return <MarketPage />
  }
  if (path.startsWith("/knowledge")) {
    return <KnowledgePage />
  }
  return <HomePage />
}
