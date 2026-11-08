#!/bin/bash
# 사용법: ./new-post.sh "글 제목" slug-name
TITLE="$1"; SLUG="$2"
FILE="_posts/$(date +%F)-$SLUG.md"
cat > "$FILE" <<EOF
---
title: $TITLE
date: $(date '+%F %T %z')
categories: []
tags: []
---

EOF
echo "생성됨: $FILE"; code "$FILE"