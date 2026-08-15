#!/usr/bin/env bash
# build.sh - generate index.html from resume.toml
#
# Usage:
#   ./build.sh            regenerate index.html
#
# Requirements:
#   - bash 4+ (substring/parameter expansion, herestrings)
#   - gawk (parses resume.toml; capture-array match() is gawk-only)
#
# The script reads resume.toml, turns it into a tab-separated event stream
# with an embedded gawk parser, then renders index.html from that data.
# All user-supplied values are HTML-escaped by the parser.
#
# TOML conventions the parser expects (see resume.toml):
#   - Quoted values must not contain double quotes, tabs, or newlines.
#   - Inline records (jobs/projects/publications) are one record per line,
#     with fields separated by ", " and an optional inline skills array.
#   - Bullet/list items are one quoted string per line.

set -euo pipefail
cd "$(dirname "$0")"

TOML="resume.toml"
OUT="index.html"
TMPDATA="$(mktemp)"
trap 'rm -f "$TMPDATA"' EXIT

command -v gawk >/dev/null 2>&1 || { echo "build.sh: gawk is required (parses $TOML)" >&2; exit 1; }
[[ -f "$TOML" ]] || { echo "build.sh: $TOML not found" >&2; exit 1; }

# ---------------------------------------------------------------------------
# parse: resume.toml -> tab-separated events on stdout
#   SCALAR\t<key>\t<value>              top-level key = "value"
#   ARRAY\t<key>\t<item>                top-level list item
#   RECORD_START\t<id>                  id = work.N | projects.N | other.N
#   RECORD\t<id>\t<key>\t<value>        record field (or skill item)
#   BULLET\t<id>\t<text>                record bullet
#   RECORD_END\t<id>
# ---------------------------------------------------------------------------
parse() {
  gawk -f - "$TOML" <<'GAWK'
BEGIN { OFS = "\t" }

# HTML-escape a value before it reaches the shell/template.
function esc(s) {
  gsub(/&/, "\\&amp;", s)
  gsub(/</, "\\&lt;", s)
  gsub(/>/, "\\&gt;", s)
  return s
}

{
  if (inarray) {
    if (inbullets) {
      # close bullets (and optionally the record, e.g. "] },")
      if ($0 ~ /^[[:space:]]*\][[:space:]]*[}],?[[:space:]]*$/) {
        inbullets = 0
        line = $0
        sub(/^[[:space:]]*\]/, "", line)
        if (line ~ /^[[:space:]]*\},?[[:space:]]*$/) { print "RECORD_END\t" rec; rec = "" }
      }
      # close bullets only ("]")
      else if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
        inbullets = 0
      }
      # bullet text
      else if ($0 ~ /^[[:space:]]*"/) {
        if (match($0, /^[[:space:]]*"([^"]*)"/, m)) print "BULLET\t" rec "\t" esc(m[1])
      }
    }
    # start of a record: inline fields, optional skills array, maybe bullets
    else if ($0 ~ /^[[:space:]]*\{/) {
      counts[array]++
      rec = array "." counts[array]
      print "RECORD_START\t" rec
      line = $0
      # extract inline skills array (["a", "b"]) if present
      if (match(line, /skills[[:space:]]*=[[:space:]]*\[[^]]*\]/)) {
        arr = substr(line, RSTART, RLENGTH)
        line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
        inner = arr
        sub(/^[^[]*\[/, "", inner)
        sub(/\][^]]*$/, "", inner)
        if (inner != "") {
          n = split(inner, items, /,/)
          for (i = 1; i <= n; i++) {
            v = items[i]; gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            print "RECORD\t" rec "\tskills\t" esc(v)
          }
        }
      }
      # extract key = "value" fields
      while (match(line, /[a-z_]+[[:space:]]*=[[:space:]]*"[^"]*"/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        if (split(tok, kv, /[[:space:]]*=[[:space:]]*/) == 2) {
          val = kv[2]; gsub(/^"|"$/, "", val)
          print "RECORD\t" rec "\t" kv[1] "\t" esc(val)
        }
      }
      # what remains on the line: bullets open, or record close
      if (line ~ /bullets[[:space:]]*=[[:space:]]*\[/) inbullets = 1
      else if (line ~ /^[[:space:]]*\},?[[:space:]]*$/) { print "RECORD_END\t" rec; rec = "" }
    }
    # record close on its own line
    else if ($0 ~ /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/) {
      print "RECORD_END\t" rec; rec = ""
    }
    # array close
    else if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
      inarray = 0; array = ""
    }
  }
  # array open: jobs = [  |  projects = [  |  publications = [
  else if ($0 ~ /^(jobs|projects|publications)[[:space:]]*=[[:space:]]*\[/) {
    inarray = 1
    if ($0 ~ /^jobs/) array = "work"
    else if ($0 ~ /^projects/) array = "projects"
    else array = "other"
    counts[array] = -1
  }
  # scalar: key = "value"
  else if ($0 ~ /^[a-z_]+[[:space:]]*=[[:space:]]*"/) {
    if (match($0, /^([a-z_]+)[[:space:]]*=[[:space:]]*"([^"]*)"/, m)) {
      print "SCALAR\t" m[1] "\t" esc(m[2])
    }
  }
  # top-level list: key = ["a", "b", ...]
  else if ($0 ~ /^[a-z_]+[[:space:]]*=[[:space:]]*\[/) {
    if (match($0, /^([a-z_]+)[[:space:]]*=[[:space:]]*\[(.*)\]/, m)) {
      inner = m[2]
      if (inner != "") {
        n = split(inner, items, /,/)
        for (i = 1; i <= n; i++) {
          v = items[i]; gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          print "ARRAY\t" m[1] "\t" esc(v)
        }
      }
    }
  }
}
GAWK
}

# ---------------------------------------------------------------------------
# load: read the parse stream into shell variables
# ---------------------------------------------------------------------------
load() {
  local tag a b c cur="" i
  local jn=0 pn=0 un=0

  while IFS=$'\t' read -r tag a b c; do
    case "$tag" in
      SCALAR)
        case "$a" in
          first_name) first_name="$b" ;;
          last_name) last_name="$b" ;;
          title) p_title="$b" ;;
          website) c_website="$b" ;;
          email) c_email="$b" ;;
          linkedin) c_linkedin="$b" ;;
          github) c_github="$b" ;;
          phone) c_phone="$b" ;;
          location) c_location="$b" ;;
          citizenship) c_citizenship="$b" ;;
          school) e_school="$b" ;;
          degree) e_degree="$b" ;;
          major) e_major="$b" ;;
          graduation) e_grad="$b" ;;
          summary) summary="$b" ;;
        esac
        ;;
      ARRAY)
        case "$a" in
          languages) sk_langs+=("$b") ;;
          frameworks) sk_frameworks+=("$b") ;;
          data) sk_data+=("$b") ;;
          tools) sk_tools+=("$b") ;;
        esac
        ;;
      RECORD_START)
        cur="$a"
        case "$cur" in
          work.*) jn=$((jn + 1)) ;;
          projects.*) pn=$((pn + 1)) ;;
          other.*) un=$((un + 1)) ;;
        esac
        ;;
      RECORD)
        case "$cur" in
          work.*)
            i=${cur#work.}
            case "$b" in
              company) j_company[i]="$c" ;;
              title) j_title[i]="$c" ;;
              start_date) j_start[i]="$c" ;;
              end_date) j_end[i]="$c" ;;
            esac
            ;;
          projects.*)
            i=${cur#projects.}
            case "$b" in
              name) p_name[i]="$c" ;;
              date) p_date[i]="$c" ;;
              github) p_link[i]="$c" ;;
              skills) p_skills[i]+=" $c" ;;
            esac
            ;;
          other.*)
            i=${cur#other.}
            case "$b" in
              title) u_title[i]="$c" ;;
              role) u_role[i]="$c" ;;
              publisher) u_pub[i]="$c" ;;
              date) u_date[i]="$c" ;;
              link) u_link[i]="$c" ;;
              description) u_desc[i]="$c" ;;
            esac
            ;;
        esac
        ;;
      BULLET)
        case "$cur" in
          work.*) i=${cur#work.}; j_bullets[i]+=$'\n'"$b" ;;
          projects.*) i=${cur#projects.}; p_bullets[i]+=$'\n'"$b" ;;
        esac
        ;;
      RECORD_END) cur="" ;;
    esac
  done
  N_JOBS=$jn; N_PROJECTS=$pn; N_PUBS=$un
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
# "2026-04" -> "April 2026"; anything else passes through
date_fmt() {
  local v="$1" m
  [[ "$v" =~ ^[0-9]{4}-[0-9]{2}$ ]] || { echo "$v"; return; }
  m=${v:5:2}
  case "$m" in
    01) m=January ;; 02) m=February ;; 03) m=March ;; 04) m=April ;;
    05) m=May ;; 06) m=June ;; 07) m=July ;; 08) m=August ;;
    09) m=September ;; 10) m=October ;; 11) m=November ;; 12) m=December ;;
    *) echo "$v"; return ;;
  esac
  echo "$m ${v:0:4}"
}

# "https://www.example.com/x/" -> "example.com/x"
display_url() {
  local u="$1"
  u="${u#https://}"; u="${u#http://}"; u="${u#www.}"
  echo "${u%/}"
}

# "Bachelor of Science" -> "B.S."
degree_short() {
  case "$1" in
    "Bachelor of Science") echo "B.S." ;;
    *) echo "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# render: write index.html to a temp file, then move it into place
# ---------------------------------------------------------------------------
render() {
  local tmp="$1" i k b
  local e_degree_short
  e_degree_short="$(degree_short "$e_degree")"

  {
    cat <<HEAD
<!-- Generated by build.sh from resume.toml. Do not edit directly. -->
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>GitanElyon Resume</title>
    <link rel="stylesheet" href="style.css">
    <script src="print.js"></script>
    <script src="scale.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
    <script src="ui.js"></script>
  </head>

  <body>
    <div class="resume-wrapper">
      <div class="container">
        <!-- Left Sidebar -->
        <aside class="sidebar">
          <div class="sidebar-header">
            <h1>$first_name</h1>
            <h2>$last_name</h2>
            <p class="title">$p_title</p>
          </div>

          <section class="sidebar-section">
            <h2>Education</h2>
            <div class="education-item">
              <p class="edu-institution">$e_school</p>
              <p class="edu-detail">$e_degree_short $e_major</p>
              <p class="edu-detail">$e_grad</p>
            </div>
          </section>

          <section class="sidebar-section">
            <h2>Publications</h2>
HEAD

    for ((i = 0; i < N_PUBS; i++)); do
      cat <<PUB
            <div class="publication-item">
              <p class="pub-title">${u_title[i]}</p>
              <p class="pub-detail">${u_role[i]} - ${u_pub[i]}, $(date_fmt "${u_date[i]}")</p>
              <p class="pub-detail">${u_desc[i]}</p>
              <a class="pub-link" href="${u_link[i]}" target="_blank">$(display_url "${u_link[i]}")</a>
            </div>
PUB
    done

    cat <<'SKILLS_MID'

          </section>

          <section class="sidebar-section">
            <h2>Skills</h2>
SKILLS_MID

    emit_skills "Languages" sk_langs
    emit_skills "Frameworks & Libraries" sk_frameworks
    emit_skills "Databases & Search" sk_data
    emit_skills "Tools & Systems" sk_tools

    cat <<CONTACT_TOP

          </section>

          <section class="sidebar-section contact-section">
            <h2>Contact</h2>
            <div class="contact-item">
              <p class="contact-label">Website</p>
              <a href="$c_website/">$(display_url "$c_website")</a>
            </div>
            <div class="contact-item">
              <p class="contact-label">GitHub</p>
              <a href="$c_github">$(display_url "$c_github")</a>
            </div>
            <div class="contact-item">
              <p class="contact-label">LinkedIn</p>
              <a href="$c_linkedin">$(display_url "$c_linkedin")</a>
            </div>
            <div class="contact-item">
              <p class="contact-label">Email</p>
              <a href="mailto:$c_email">$c_email</a>
            </div>
            <div class="contact-item">
              <p class="contact-label">Phone</p>
              <p>$c_phone</p>
            </div>
            <div class="contact-item">
              <p class="contact-label">Location</p>
              <p>$c_location</p>
            </div>
            <div class="contact-item">
              <p class="contact-label">Citizenship</p>
              <p>$c_citizenship</p>
            </div>
          </section>
        </aside>

        <!-- Main Content -->
        <main class="main-content">
          <section class="content-section">
            <h2>Summary</h2>
            <p>$summary</p>
          </section>

          <section class="content-section">
            <h2>Professional Experience</h2>
CONTACT_TOP

    for ((i = 0; i < N_JOBS; i++)); do
      cat <<JOB
            <div class="job">
              <h3>${j_title[i]}</h3>
              <p class="job-meta">${j_company[i]} | $(date_fmt "${j_start[i]}") - $(date_fmt "${j_end[i]}")</p>
              <ul>
JOB
      while IFS= read -r b; do
        [[ -n "$b" ]] && echo "                <li>$b</li>"
      done <<<"${j_bullets[i]}"
      cat <<'JOB_END'
              </ul>
            </div>
JOB_END
    done

    cat <<'PROJ_HEAD'

          </section>

          <section class="content-section">
            <h2>Technical Projects</h2>
PROJ_HEAD

    for ((i = 0; i < N_PROJECTS; i++)); do
      cat <<PROJ
            <div class="job">
              <h3>${p_name[i]}</h3>
              <p class="job-meta">${p_skills[i]# } | $(date_fmt "${p_date[i]}")</p>
              <ul>
PROJ
      local -a lines=()
      while IFS= read -r b; do
        [[ -n "$b" ]] && lines+=("$b")
      done <<<"${p_bullets[i]}"
      local last=$(( ${#lines[@]} - 1 ))
      for ((k = 0; k < ${#lines[@]}; k++)); do
        if [[ $k -eq $last && "${p_link[i]}" != "private" ]]; then
          echo "                <li>${lines[k]} <a href=\"${p_link[i]}\">GitHub Repository</a></li>"
        else
          echo "                <li>${lines[k]}</li>"
        fi
      done
      cat <<'PROJ_END'
              </ul>
            </div>
PROJ_END
    done

    cat <<'FOOT'
          </section>
        </main>
      </div>
    </div>
    <a href="https://gitanelyon.dev" class="website-btn" aria-label="Visit Website">
      <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>
      </svg>
    </a>
    <button class="download-btn" aria-label="Download PDF">
      <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/>
      </svg>
    </button>
  </body>
</html>
FOOT
  } >"$tmp"
}

# emit_skills <label> <bash-array-name> - one <h3> block per non-empty category
emit_skills() {
  local label="$1"
  local -n items="$2"
  (( ${#items[@]} == 0 )) && return
  cat <<H3
            <div class="skill-category">
              <h3>$label</h3>
              <ul class="skill-list">
H3
  for item in "${items[@]}"; do
    echo "                <li>$item</li>"
  done
  cat <<H3_END
              </ul>
            </div>
H3_END
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
parse >"$TMPDATA" || { echo "build.sh: failed to parse $TOML" >&2; exit 1; }
[[ -s "$TMPDATA" ]] || { echo "build.sh: no data parsed from $TOML" >&2; exit 1; }

load <"$TMPDATA"

# validate required fields before rendering anything
for v in first_name last_name p_title c_website summary e_school e_major e_grad; do
  [[ -n "${!v:-}" ]] || { echo "build.sh: missing required field '$v' in $TOML" >&2; exit 1; }
done
[[ "$N_JOBS" -gt 0 ]] || { echo "build.sh: no jobs found in $TOML" >&2; exit 1; }

TMPOUT="$(mktemp)"
trap 'rm -f "$TMPDATA" "$TMPOUT"' EXIT
render "$TMPOUT"
mv -f "$TMPOUT" "$OUT"

echo "build.sh: regenerated $OUT from $TOML"
