![create-autorun icon](images/create-autorun.readme.png)

## Description

This is a run-once BASH script to create an autorun environment on your QNAP NAS. This can be used to automatically execute your own scripts when the NAS boots-up.


## What it does

This installer script writes an `autorun.sh` processor into your default volume, below the **.system directory**. It then symlinks this from the DOM back to your default data volume so that it is run on NAS startup. This means you don't need to load the DOM partition every time you want to change the contents of `autorun.sh`. 

## How to create your autorun.sh

    curl -skL https://git.io/create-autorun | sudo bash

## Notes

- If you didn't have an `autorun.sh` file before, then the `autorun.sh` file created by this utility will contain a script directory processor, and make a a scripts directory available for your own shell-scripts. Everything in this scripts directory is run (in-order) during NAS startup by the default `autorun.sh` file created only. The notes below are only applicable to the `autorun.sh` written by this utility. If you already had another `autorun.sh` file, then it will remain and be used instead, and the following notes won't apply.

- The location of the autorun system will depend on your default volume name. For example: if your default volume is `CACHEDEV1_DATA`, then the automatic script processor will be created at:
```
/share/CACHEDEV1_DATA/.system/autorun/autorun.sh
```
... and the scripts directory will be created at:
```
/share/CACHEDEV1_DATA/.system/autorun/scripts/
```

- `autorun.sh` is triggered at some point during NAS bootup, which then runs each executable file in the scripts directory in the default filename list order. If you need to run one script before the other, prefix them with a number such as:

```
10-example.sh
20-example.sh
25-example.sh
30-example.sh
```

- A log file is created during `autorun.sh` execution. It is located at `/var/log/autorun.log` and contains the date-time and name of each of the scripts found in the scripts directory as they were run, as well as any captured stdout.
