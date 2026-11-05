#!/usr/bin/env bash
# rtl_audit.sh — iOS RTL Layout Auditor
# Usage: ./rtl_audit.sh [path/to/project]
# Scans Swift source files for common RTL anti-patterns.

set -euo pipefail

PROJECT_DIR="${1:-.}"
SWIFT_FILES=$(find "$PROJECT_DIR" -name "*.swift" -not -path "*/Pods/*" -not -path "*/.build/*" -not -path "*/DerivedData/*")

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔍 iOS RTL Audit — $(date '+%Y-%m-%d %H:%M')"
echo "  📁 Project: $PROJECT_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL_ISSUES=0

# ─────────────────────────────────────────────
# Helper: report matches
# ─────────────────────────────────────────────
report() {
  local severity="$1"
  local pattern="$2"
  local label="$3"
  local fix="$4"

  local matches
  matches=$(echo "$SWIFT_FILES" | xargs grep -rn --include="*.swift" "$pattern" 2>/dev/null || true)

  if [ -n "$matches" ]; then
    local count
    count=$(echo "$matches" | wc -l | tr -d ' ')
    TOTAL_ISSUES=$((TOTAL_ISSUES + count))

    if [ "$severity" = "error" ]; then
      echo -e "${RED}❌ [$count hits] $label${NC}"
    else
      echo -e "${YELLOW}⚠️  [$count hits] $label${NC}"
    fi
    echo -e "   Fix: ${BLUE}$fix${NC}"
    echo "$matches" | head -5 | sed 's/^/   /'
    [ "$(echo "$matches" | wc -l)" -gt 5 ] && echo "   ... (showing first 5)"
    echo ""
  fi
}

# ─────────────────────────────────────────────
# CRITICAL ERRORS — definite RTL breaks
# ─────────────────────────────────────────────
echo -e "${RED}■ CRITICAL — These will break RTL layouts${NC}"
echo "─────────────────────────────────────────────────"

report "error" \
  "\.leftAnchor\|\.rightAnchor" \
  "Absolute leftAnchor / rightAnchor (doesn't flip in RTL)" \
  "Replace with .leadingAnchor / .trailingAnchor"

report "error" \
  "textAlignment\s*=\s*\.left\|textAlignment\s*=\s*\.right" \
  "Hardcoded text alignment (.left / .right)" \
  "Replace with .natural (UIKit) or .leading (SwiftUI)"

report "error" \
  "alignment:\s*\.left\b\|alignment:\s*\.right\b" \
  "SwiftUI hardcoded alignment (.left / .right)" \
  "Replace with .leading / .trailing"

report "error" \
  "\.frame\.origin\.x\s*=" \
  "Hardcoded frame.origin.x assignment (absolute position)" \
  "Use Auto Layout leading/trailing constraints instead"

report "error" \
  "NSLayoutConstraint.*constant.*left\|NSLayoutConstraint.*constant.*right" \
  "Possible absolute NSLayoutConstraint (check for left/right)" \
  "Use leadingAnchor / trailingAnchor"

# ─────────────────────────────────────────────
# WARNINGS — likely RTL issues
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}■ WARNINGS — Likely RTL issues, review carefully${NC}"
echo "─────────────────────────────────────────────────"

report "warning" \
  "padding(.leading\|padding(.trailing" \
  "Hardcoded padding direction (verify .leading/.trailing are intentional)" \
  "These are correct IF semantic. Verify no absolute .left/.right padding exists"

report "warning" \
  "CGAffineTransform(translationX:" \
  "Hardcoded X translation (may need RTL flip)" \
  "Multiply x value by RTL direction: isRTL ? -x : x"

report "warning" \
  "\.offset(x:" \
  "Hardcoded SwiftUI x offset (may need RTL flip)" \
  "Use environment layoutDirection to conditionally negate offset"

report "warning" \
  "UIEdgeInsets(top.*left.*bottom.*right" \
  "UIEdgeInsets with absolute left/right (doesn't flip)" \
  "Use NSDirectionalEdgeInsets(top:leading:bottom:trailing:) instead"

report "warning" \
  "flipsForRightToLeftLayoutDirection(false)" \
  "Explicit RTL flip disabled (verify this is intentional)" \
  "Only use false for logos, maps, video — add // RTL: intentionally LTR comment"

report "warning" \
  "semanticContentAttribute\s*=\s*\.forceLeftToRight" \
  "Forced LTR semantic content (verify intentional)" \
  "Only use for maps, media, logos — add // RTL: intentionally LTR comment"

# ─────────────────────────────────────────────
# INFO — Checks to verify
# ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}■ INFO — Verify these are locale-aware${NC}"
echo "─────────────────────────────────────────────────"

report "warning" \
  'String(format:\|NSString(format:' \
  "String format calls (ensure %@ args are locale-aware)" \
  "Use locale-aware formatters; avoid manual number formatting"

report "warning" \
  "DateFormatter()\|NumberFormatter()" \
  "Formatter instances (verify .locale = .current is set)" \
  "Add: formatter.locale = .current"

report "warning" \
  '"left"\|"right"\|"Left"\|"Right"' \
  'String literals containing "left"/"right" (may indicate hardcoded direction in logic)' \
  "Review — may be fine for non-UI strings"

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$TOTAL_ISSUES" -eq 0 ]; then
  echo -e "  ${GREEN}✅ No RTL issues found! Project looks RTL-ready.${NC}"
else
  echo -e "  ${RED}⚠️  Found $TOTAL_ISSUES potential RTL issues${NC}"
  echo ""
  echo "  Next steps:"
  echo "   1. Fix CRITICAL errors first (definite layout breaks)"
  echo "   2. Review WARNINGS (context-dependent)"
  echo "   3. Test with -AppleLanguages '(ar)' launch argument"
  echo "   4. Run the QA checklist in Documentation/Testing-RTL.md"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
