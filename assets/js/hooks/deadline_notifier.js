const DeadlineNotifier = {
  mounted() {
    this.handleEvent("notify-deadlines", (payload) => {
      if (!("Notification" in window)) return

      if (Notification.permission === "granted") {
        this.fireNotification(payload)
      } else if (Notification.permission !== "denied") {
        Notification.requestPermission().then((permission) => {
          if (permission === "granted") this.fireNotification(payload)
        })
      }
    })
  },

  fireNotification({overdue, near}) {
    if (overdue === 0 && near === 0) return

    const lines = []
    if (overdue > 0) lines.push(`超過: ${overdue}件`)
    if (near > 0) lines.push(`30日以内: ${near}件`)

    new Notification("歩み — モニタリング期限", {
      body: lines.join("\n"),
      tag: "ayumi-deadline",
    })
  },
}

export default DeadlineNotifier
