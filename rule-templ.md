# AI WORKSPACE RULES

## A) RULES TO FOLLOW (Manual - Require Human/AI Judgment)

### WORKSPACE ORGANIZATION
1. Everything has its place. Maintain organized workspace structure.
2. Each container/project gets its own directory containing all related files.
3. Use iteration directories (v1/, v2/) within projects when iterating.
6. New projects start in `./projects/wip/[project-name]/`, move to `./projects/complete/` when requirements met.
7. Project documentation in `./docs/[project]/`.
8. External documentation, failure prevention guides, and learned patterns in `./kb/[category]/[title]`.

### TASK COMPLETION  
12. Work isn't done until every aspect is complete, tested, and documented.
13. Include itemized cleanup steps in all todos.
15. Discovered incomplete todos → move to `./todo/` and add to current list.
16. Clean up your mess. Fix problems you discover.
21. Todos must be detailed roadmaps with accurate timestamps for each edit.

### DATA MANAGEMENT
17. Purging = complete removal of data, configs, and directories.

### SECURITY & CODE QUALITY
23. Test before marking complete. Document test commands in project README.
24. Follow existing code style. Run linters/formatters before completion.

### VERSION CONTROL
26. Commit with descriptive messages after each logical unit of work.
27. Never commit broken code to main branch. Use trunk-based development.

### DEPENDENCIES & RESOURCES
28. Document all dependencies in appropriate manifest (requirements.txt, package.json, etc.).
30. Clean up resources: close connections, stop services, free memory.

### ETHICS & TEAMWORK
31. No lying, misleading, or intentional misunderstanding.
32. Point out pitfalls; don't maliciously comply.
33. We're a team. Share blame and praise equally.
34. If we can do better, we must do better.

### ACCOUNTABILITY
35. No laziness. Incomplete work becomes someone else's burden.

### FAILURE MANAGEMENT
37. Document failure patterns. Create prevention guides in `./kb/failures/[title]`.
38. Conduct weekly failure reviews to identify patterns and improvements.

### COMMUNICATION
39. Leave clear comments for non-obvious decisions.
40. Document breaking changes and migration paths.

---

## B) RULES THAT HAPPEN AUTOMATICALLY

### WORKSPACE ORGANIZATION (Automated)
**4.** Single-use scripts: delete after success, move failures to `./fuckups/` *(manual)*, purge after 14 days *(automated)*
**5.** Project scripts organized in `./scripts/[language]/`, reusable utilities in `./utilities/` *(file watcher)*
**9.** Build outputs to `./artifacts/[project]/`, retain for 7 days *(daily cleanup)*
**10.** Clean `./temp/` daily, purge files older than 24 hours *(daily cleanup)*
**11.** External repositories clone to `./repos/`, maintain upstream sync *(manual clone, automated sync possible)*

### TASK COMPLETION (Automated)
**14.** Completed todos → `./tododone/[project]/` with completion timestamp *(via `./automate.sh todo`)*

### DATA MANAGEMENT (Automated) 
**18.** Create backup before destructive operations *(via `./automate.sh backup`)*
**19.** Archive completed projects to `./backups/[project]/` before moving to complete *(via automation)*
**20.** Daily incremental backup of entire workspace to `./backups/daily/[date]/` *(cron 2 AM)*

### SECURITY & CODE QUALITY (Automated)
**22.** Never commit secrets/keys *(git pre-commit hook scans)*
**25.** Set appropriate file permissions (configs: 600, scripts: 755, data: 644) *(git pre-commit hook)*

### DEPENDENCIES & RESOURCES (Automated)
**29.** Auto-update dependencies. Review security advisories *(can be automated)*

### ACCOUNTABILITY (Automated)
**36.** Track all rule references in `./rules/[rule-number].txt` *(via `./automate.sh track N`)*

---

## Quick Reference

**Call directly from AI:**
```bash
./automate.sh backup project /path/to/project  # Before destructive ops (Rule 18)
./automate.sh todo task.txt project-name       # Complete todo (Rule 14)  
./automate.sh track 15                         # Track rule usage (Rule 36)
./automate.sh organize                         # Manual file organization
```

**Automated background:**
- File watcher organizes new files by pattern (Rules 5, 9)
- Daily cleanup: temp files, old artifacts, full backup (Rules 9, 10, 20)
- Git hooks: secrets scan, linting, permissions (Rules 22, 25)