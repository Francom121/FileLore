import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Mail, Send, CheckCircle2, AlertCircle } from "lucide-react"

type Status = "idle" | "sending" | "sent" | "error"

function encode(data: Record<string, string>) {
  return Object.keys(data)
    .map((key) => encodeURIComponent(key) + "=" + encodeURIComponent(data[key]))
    .join("&")
}

export default function Contact() {
  const [status, setStatus] = useState<Status>("idle")
  const [form, setForm] = useState({ name: "", email: "", message: "" })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setStatus("sending")
    try {
      const res = await fetch("/", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: encode({ "form-name": "contact", ...form }),
      })
      if (!res.ok) throw new Error(String(res.status))
      setStatus("sent")
    } catch {
      setStatus("error")
    }
  }

  const inputClass =
    "w-full rounded-xl border border-ink/15 bg-white px-4 py-3 text-[15px] text-ink placeholder:text-ink/35 outline-none transition focus:border-fl-500 focus:ring-2 focus:ring-fl-500/30"

  return (
    <section id="contact" className="bg-white">
      <div className="mx-auto max-w-xl px-6 py-20 md:py-24">
        <div className="text-center">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-fl-500/15 text-fl-600">
            <Mail className="h-7 w-7" />
          </div>
          <h2 className="mt-6 text-3xl font-semibold tracking-tight text-ink">
            Questions? Found a bug?
          </h2>
          <p className="mx-auto mt-4 max-w-md text-lg leading-relaxed text-ink/65">
            FileLore is a one-person project — every message lands directly in
            the maker's inbox.
          </p>
        </div>

        {status === "sent" ? (
          <div className="mt-10 flex flex-col items-center gap-3 rounded-2xl border border-fl-500/30 bg-fl-50 px-6 py-10 text-center">
            <CheckCircle2 className="h-9 w-9 text-fl-600" />
            <p className="text-lg font-semibold text-ink">Message sent!</p>
            <p className="text-[15px] text-ink/60">
              Thanks for reaching out — you'll hear back soon.
            </p>
          </div>
        ) : (
          <form
            name="contact"
            method="POST"
            data-netlify="true"
            netlify-honeypot="bot-field"
            onSubmit={handleSubmit}
            className="mt-10 flex flex-col gap-4"
          >
            <input type="hidden" name="form-name" value="contact" />
            <p className="hidden">
              <label>
                Don't fill this out: <input name="bot-field" />
              </label>
            </p>
            <div className="grid gap-4 sm:grid-cols-2">
              <input
                required
                name="name"
                placeholder="Your name"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                className={inputClass}
              />
              <input
                required
                type="email"
                name="email"
                placeholder="Your email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                className={inputClass}
              />
            </div>
            <textarea
              required
              name="message"
              placeholder="What's up? Bug reports, feature ideas, questions — all welcome."
              rows={5}
              value={form.message}
              onChange={(e) => setForm({ ...form, message: e.target.value })}
              className={inputClass + " resize-y"}
            />
            {status === "error" && (
              <p className="flex items-center justify-center gap-2 text-[14px] text-red-600">
                <AlertCircle className="h-4 w-4" />
                Something went wrong — please try again.
              </p>
            )}
            <Button
              type="submit"
              size="lg"
              disabled={status === "sending"}
              className="mt-2 h-12 bg-fl-500 px-8 text-base font-semibold text-ink hover:bg-fl-400 disabled:opacity-60"
            >
              <Send className="mr-2 h-5 w-5" />
              {status === "sending" ? "Sending…" : "Send message"}
            </Button>
          </form>
        )}
      </div>
    </section>
  )
}
