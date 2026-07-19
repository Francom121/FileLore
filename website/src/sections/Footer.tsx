export default function Footer() {
  return (
    <footer className="border-t border-white/10 bg-ink text-white/50">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-3 px-6 py-8 text-sm sm:flex-row">
        <div className="flex items-center gap-2.5">
          <img
            src="/logo-512.png"
            alt=""
            className="h-5 w-5 rounded-[6px] opacity-80"
          />
          <span>© 2026 FileLore</span>
        </div>
        <p>Windows version in the works.</p>
      </div>
    </footer>
  )
}
