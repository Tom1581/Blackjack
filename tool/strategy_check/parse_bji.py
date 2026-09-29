import re,sys
def parse(path):
    s=open(path).read()
    out={}
    for label in ['Hard Totals','Soft Totals','Pairs']:
        i=s.index(f'aria-label="{label} strategy"')
        j=s.index('</table>',i)
        t=s[i:j]
        rows=re.findall(r'<tr><th scope="row">(.*?)</th>(.*?)</tr>',t)
        out[label]=[(re.sub('<.*?>','',r[0]), re.findall(r'data-act="([^"]+)"',r[1])) for r in rows]
    return out
if __name__=='__main__':
    o=parse(sys.argv[1])
    for k,v in o.items():
        print('==',k)
        for name,acts in v:
            print(f'{name:>6}', ' '.join(f'{a:>2}' for a in acts))
    # settings echo
    s=open(sys.argv[1]).read()
    for m in re.findall(r'(House edge[^<]{0,80})',s)[:3]: print(m)
