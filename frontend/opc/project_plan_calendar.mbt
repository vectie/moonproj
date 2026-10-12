///|
extern "js" fn plan_calendar_download(text : String) =
  #| text => { const u = URL.createObjectURL(new Blob([text], {type: "text/calendar;charset=utf-8"})); const a = document.createElement("a"); a.href = u; a.download = "plan-milestones.ics"; a.click(); setTimeout(() => URL.revokeObjectURL(u), 1000); }
