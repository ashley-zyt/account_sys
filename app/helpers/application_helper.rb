module ApplicationHelper
  def status_badge(status)
    labels = { 0 => "未启动", 1 => "待执行", 2 => "执行中", 3 => "执行完成", 4 => "任务失败" }
    colors = {
      0 => { bg: "rgba(100,116,139,0.16)", border: "rgba(100,116,139,0.4)", color: "#94a3b8" },
      1 => { bg: "rgba(251,191,36,0.16)", border: "rgba(251,191,36,0.4)", color: "#fbbf24" },
      2 => { bg: "rgba(59,130,246,0.16)", border: "rgba(59,130,246,0.4)", color: "#93c5fd" },
      3 => { bg: "rgba(34,197,94,0.16)", border: "rgba(34,197,94,0.4)", color: "#86efac" },
      4 => { bg: "rgba(239,68,68,0.16)", border: "rgba(239,68,68,0.4)", color: "#fca5a5" }
    }
    c = colors[status] || colors[0]
    content_tag :span, style: "display:inline-flex;align-items:center;gap:4px;padding:3px 10px;background:#{c[:bg]};border:1px solid #{c[:border]};border-radius:999px;color:#{c[:color]};font-size:12px;white-space:nowrap;" do
      content_tag(:span, "", style: "width:6px;height:6px;border-radius:50%;background:#{c[:color]};") +
      (labels[status] || "未知")
    end
  end
end
