"""Normalize Gowin HTML timing tables for the existing implementation checks."""
import html
from pathlib import Path
import re
import sys

source, destination = map(Path, sys.argv[1:3])
content = source.read_text(encoding='utf-8')

def rows(anchor):
    section=content.split('name="'+anchor+'"',1)[1]
    table=re.search(r'<table\b[^>]*>(.*?)</table>',section,re.S)[1]
    result=[]
    for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>',table,re.S):
        cells=re.findall(r'<td\b[^>]*>(.*?)</td>',row,re.S)
        if cells:
            result.append([html.unescape(re.sub(r'<[^>]*>','',cell)).strip() for cell in cells])
    return result

lines=['Derived from '+str(source)+'; normalized HTML tables, not a native text report.']
for row in rows('Total_Negative_Slack_Report'):
    lines.append(' '.join(row))
sections=[('Setup_Slack_Table','3.1.1 Setup Paths Table'),
          ('Hold_Slack_Table','3.1.2 Hold Paths Table'),
          ('Recovery_Slack_Table','3.1.3 Recovery Paths Table'),
          ('Removal_Slack_Table','3.1.4 Removal Paths Table'),
          ('MIN_PULSE_WIDTH_TABLE','3.2 Minimum Pulse Width Table')]
for anchor,title in sections:
    lines+=['',title]+[' '.join(row) for row in rows(anchor)]+['']
for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>',content,re.S):
    cells=[html.unescape(re.sub(r'<[^>]*>','',c)).strip()
           for c in re.findall(r'<td\b[^>]*>(.*?)</td>',row,re.S)]
    if cells and cells[0].startswith('TC_'):
        lines.append(' '.join(cells))
destination.write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Normalized HTML timing tables:',destination)
