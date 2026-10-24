#!/usr/bin/env python3
"""Maintain the local caelestia-cli smart-light threshold patch. Check by default."""
from pathlib import Path
import argparse,datetime,os,shutil,subprocess,sys
import caelestia.utils.wallpaper as wallpaper
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--apply',action='store_true');a=ap.parse_args()
target=Path(wallpaper.__file__);base=target.parents[2]
patch=Path(__file__).resolve().parents[1]/'patches/cli/smart-light-threshold.patch'
def run(reverse=False,dry=True):
 args=['patch','--batch','-p1','-d',str(base), '--reverse' if reverse else '--forward']
 if dry:args.append('--dry-run')
 return subprocess.run(args,input=patch.read_bytes(),capture_output=True)
if run(reverse=True).returncode==0:print('CLI smart-light threshold patch already installed.');sys.exit(0)
if run().returncode:sys.exit('Installed CLI does not match this patch; review the package update first.')
if not a.apply:print('Patch applies cleanly. Run with sudo and --apply to install.');sys.exit(0)
if os.geteuid()!=0:sys.exit('Root is required for --apply. Run with sudo; enter the password in your own terminal.')
b=Path('/home/caster/Documents/bakFiles')/target.relative_to('/');b=b.with_name(b.name+'-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-before-smart-threshold');b.parent.mkdir(parents=True,exist_ok=True)
if b.exists():sys.exit('Backup collision; stop.')
shutil.copy2(target,b);r=run(dry=False)
if r.returncode:
 shutil.copy2(b,target);sys.exit('Patch failed; restored original source. '+r.stderr.decode())
compile(target.read_bytes(),str(target),'exec');print('Installed. Backup:',b)
