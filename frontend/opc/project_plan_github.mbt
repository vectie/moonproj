///|
// Local saved issue export conversion; no GitHub network access.
extern "js" fn plan_github_convert_json(source : String) -> String =
  #| source => {
  #|   try {
  #|     if (source.length > 1000000) throw Error("Split exports larger than 1,000,000 characters");
  #|     const issues = JSON.parse(source.replace(/^\uFEFF/, ""));
  #|     if (!Array.isArray(issues)) throw Error("Expected a gh issue list JSON array");
  #|     const notes = ["GitHub issue planning snapshot", "Only open issues become planning tasks. Assignees, labels, milestones and closed state are source context, not MoonProj assignments or completion evidence. Set owners, milestones, dependencies and budget explicitly. Keep the original export."];
  #|     const tasks = [], seen = new Set(); let excluded = 0;
  #|     for (const issue of issues) {
  #|       if (!issue || typeof issue !== "object" || Array.isArray(issue)) throw Error("Expected issue objects");
  #|       if (!Number.isSafeInteger(issue.number) || issue.number < 1 || typeof issue.title !== "string" || !issue.title.trim()) throw Error("Each issue needs a positive number and title");
  #|       if (typeof issue.url !== "string") throw Error("Each issue needs its GitHub issue URL");
  #|       const match = /^https:\/\/([^/]+)\/([^/]+)\/([^/]+)\/issues\/([1-9][0-9]*)$/.exec(issue.url);
  #|       if (!match || Number(match[4]) !== issue.number) throw Error("Issue URL and number must match");
  #|       const id = "gh-" + [match[1],match[2],match[3],match[4]].map(encodeURIComponent).join("-");
  #|       if (seen.has(issue.url)) throw Error("Duplicate issue URL: " + issue.url);
  #|       seen.add(issue.url);
  #|       if (issue.state !== "OPEN" && issue.state !== "CLOSED") throw Error("Issue state must be OPEN or CLOSED");
  #|       if (issue.state === "CLOSED") { excluded++; continue; }
  #|       if (issue.body != null && typeof issue.body !== "string") throw Error("Issue body must be text");
  #|       if (issue.assignees != null && !Array.isArray(issue.assignees)) throw Error("Issue assignees must be an array");
  #|       if (issue.labels != null && !Array.isArray(issue.labels)) throw Error("Issue labels must be an array");
  #|       notes.push("Source issue (preview task ID: " + id + ")", JSON.stringify({number:issue.number,title:issue.title,url:issue.url,body:issue.body || "",assignees:issue.assignees || [],milestone:issue.milestone || null,labels:issue.labels || []},null,2));
  #|       tasks.push({id,name:issue.title,owner:"",milestone:"",cost:"",dependencies:[]});
  #|     }
  #|     if (!tasks.length || tasks.length > 100) throw Error("Choose between 1 and 100 open issues");
  #|     if (new Set(tasks.map(t => t.id)).size !== tasks.length) throw Error("Issue identity collision; split exports by repository");
  #|     notes.push(tasks.length + " open issues imported; " + excluded + " closed issues excluded.");
  #|     const template = JSON.stringify({format:"moonproj-plan-template/v1",notes:notes.join("\n"),currency:"",limit:"",contingency:"",owners:[{id:"planning-owner",name:"Planning preparer",role:"Assign imported work explicitly"}],tasks,milestones:[],risks:[]});
  #|     if (template.length > 1000000) throw Error("Converted plan is too large; split the export");
  #|     return JSON.stringify({error:"",template});
  #|   } catch (error) { return JSON.stringify({error:"GitHub import: " + error.message,template:""}); }
  #| }

///|
fn plan_github_read_template(
  source : String,
) -> @plan_workbench.Template raise @plan_workbench.InputError {
  let result = @json.parse(plan_github_convert_json(source)) catch {
    _ => raise @plan_workbench.Invalid("GitHub import returned invalid JSON")
  }
  guard result is { "error": String(error), "template": String(template), .. } else {
    raise @plan_workbench.Invalid("GitHub import returned an invalid result")
  }
  if !error.is_empty() {
    raise @plan_workbench.Invalid(error)
  }
  @plan_workbench.read_template(template)
}
