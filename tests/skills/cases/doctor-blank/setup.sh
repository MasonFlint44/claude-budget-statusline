# Installed with an inline CLAUDE_CONFIG_DIR knob pointing at a second config
# dir whose credentials carry no OAuth token (an API-key session). The CLI
# itself keeps the runner's real credentials in $CFG; the doctor, run with
# the knob as the statusLine command has it, must report the missing token,
# and the answer must name the login rather than guess.
scaffold_installed "CLAUDE_CONFIG_DIR=$WORK/cfg2 "
mkdir -p "$WORK/cfg2"; printf '{"primaryApiKey":"sk-ant-test"}\n' > "$WORK/cfg2/.credentials.json"
