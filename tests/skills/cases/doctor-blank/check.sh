expect_out "no OAuth token"          # the doctor's own line reached the user
expect_out "bars:"                    # and its verdict
case "$OUT" in *"/login"*|*"log in"*|*"login"*) ;; *) echo "    output never mentions logging in"; fail=$((fail + 1)) ;; esac
expect "$(jq -r .statusLine.command "$CFG/settings.json")" "CLAUDE_CONFIG_DIR=$WORK/cfg2 bash $CFG/statusline/budget-statusline.sh"   # settings untouched
case "$OUT" in *sk-ant-test*) echo "    the key leaked into the answer"; fail=$((fail + 1)) ;; esac
