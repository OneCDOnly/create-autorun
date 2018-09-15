## Description

This is a run-once BASH script to create an autorun environment on your QNAP NAS. This can be used to automatically execute your own scripts when the NAS boots-up.


## What it does

This installer script writes an autorun.sh processor into your default volume, below the .system directory. It then symlinks this into the DOM so that it's triggered on NAS startup. It also creates a scripts directory for your own custom creations and NAS modifications. Everything in the scripts directory is run (in order) during NAS startup.


## Running the installer

    curl -sk https://raw.githubusercontent.com/onecdonly/create-autorun/master/create-autorun.sh | bash

## Notes

- For those with QTS 4.3.x, you'll also need to let QTS know that it should permit the autorun.sh script to execute. Navigate to Control Panel -> System -> Hardware, then enable the option "Run user defined processes during startup".

- The location of the autorun system will depend on your default volume name. For example: my default volume is 'MD0_DATA', so the automatic processor is created at:
    /share/MD0_DATA/.system/autorun/autorun.sh

    ... and the scripts directory is created at:
    /share/MD0_DATA/.system/autorun/scripts/

- autorun.sh is triggered at some point during NAS bootup, which then runs each executable file in the scripts directory in the default filename list order. If you need to run one script before the other, prefix them with a number such as:

```
    010-example.sh
    020-example.sh
    025-example.sh
```

- A log file is created during autorun.sh execution. It is located at /var/log/autorun.log and contains the date-time and name of each of the scripts found in the scripts directory as they were run, as well as any captured stdout.