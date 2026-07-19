import Nav from "@/sections/Nav"
import Hero from "@/sections/Hero"
import AICreators from "@/sections/AICreators"
import Features from "@/sections/Features"
import HowItWorks from "@/sections/HowItWorks"
import DemoVideo from "@/sections/DemoVideo"
import DownloadCTA from "@/sections/DownloadCTA"
import Support from "@/sections/Support"
import Footer from "@/sections/Footer"

export default function Home() {
  return (
    <div className="min-h-screen bg-white font-sans">
      <Nav />
      <main>
        <Hero />
        <AICreators />
        <Features />
        <HowItWorks />
        <DemoVideo />
        <DownloadCTA />
        <Support />
      </main>
      <Footer />
    </div>
  )
}
