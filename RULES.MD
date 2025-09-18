**Server Management Rules**

## Directory Structure
```
/usr/local/bin/          # Custom system scripts
/usr/local/sbin/         # Custom admin scripts
/opt/custom/             # Custom applications
/etc/[service]/          # Service configurations
/var/log/[service]/      # Service logs
/var/lib/[service]/      # Service data
/var/backups/            # Configuration backups
/tmp/scripts/            # Temporary/test scripts
```

## Script Lifecycle
1. **Development**: Create in `/tmp/scripts/`
2. **Testing**: Name with `.test` suffix
3. **Production**: Move to `/usr/local/bin/`, make executable
4. **Cleanup**: Delete test scripts after verification
5. **One-offs**: Delete immediately after running

## Configuration Management
1. **Before editing**: `cp config config.bak.$(date +%Y%m%d)`
2. **After editing**: Test service, document changes
3. **If it breaks**: Restore from backup immediately
4. **Weekly cleanup**: Remove backups older than 30 days

## Service Deployment
1. Stop service
2. Backup current state
3. Apply changes
4. Test thoroughly
5. Document in `/var/log/changes.log`
6. Remove temporary files

## Monitoring & Logs
- System changes → `/var/log/changes.log`
- Custom scripts → `/var/log/custom/`
- Rotate logs weekly
- Archive logs older than 90 days

## Communication Rules
- **Normal mode**: Conversational, explain what user is asking for before doing it
- **Focus mode**: Direct and concise, minimal explanation
- State what you're doing and why
- Ask when unclear, don't assume
- Confirm understanding of complex tasks before executing

## Task Execution
1. **Before starting any request**: Verify date/time and working directory
2. **Then**: Explain what user is asking for
3. **On completion**: Report date/time again
4. Understand requirement fully
5. Use TodoWrite for >3 steps
6. Complete each step before moving on
7. Test before marking complete
8. Clean up all temporary resources
9. Document what was done

## Definitions
- **Request**: Any ask from the user (single command to complex project)
- **Task**: Single discrete action (edit file, run command)
- **Job**: Multiple related tasks (set up service, configure system)
- **Project**: Multiple jobs with shared goal (deploy application stack)

## Security Practices
- Never store passwords in scripts
- Use 600 permissions for sensitive files
- Audit logs before sharing
- Validate all user input
- Use absolute paths in scripts

## Failure Handling
1. Stop immediately
2. Document what failed
3. Restore to known good state
4. Investigate root cause
5. Update documentation

## Collaboration Protocol
- **Permission to interrupt**: User can stop me anytime with "stop" or "wait"
- **Going off-track**: User should redirect if I misunderstand
- **Resource usage**: Check disk space before large operations
- **Autonomy level**: Proceed with reversible changes, ask before permanent ones
- **Context switching**: Save state when switching between requests

## Git Commits
- One logical change per commit
- Message format: `[component]: action taken`
- Never commit: secrets, logs, temp files
- Test before committing

## System Inventory
Maintain in `/var/log/system-inventory.md`:
- Installed services and versions
- Custom scripts and their purpose
- Modified configurations
- Active monitoring/automation
- Port usage and firewall rules

## Cleanup Protocol
After every session:
- Delete temp files in `/tmp/`
- Close open connections
- Stop test services
- Document incomplete work
- Update relevant logs
- Update system inventory if needed