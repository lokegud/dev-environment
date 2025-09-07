**Server Rules**

**Global Rules**
# A) RULES TO FOLLOW (Manual - Require Human/AI Judgment)

### WORKSPACE ORGANIZATION
1. Everything has its place. Maintain organized workspace structure.
2. Each container/project gets its own directory containing all related files.
3. Use iteration directories (v1/, v2/) within projects when iterating.
6. New projects start in `./projects/wip/[project-name]/`, move to `./projects/complete/` when requirement>
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
