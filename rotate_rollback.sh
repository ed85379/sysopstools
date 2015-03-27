#!/bin/sh

DIR=/opt/app
CODEDIR="${DIR}/release_03_rails_update"
ROLLBACK="${DIR}/release_03_rails_update.rollback"

RollbackRotate () {
if [ -d $ROLLBACK ] ; then
  CNT=1
  let P_CNT=CNT-1
  if [ -d ${ROLLBACK}.1 ] ; then
    printf "[$(hostname -s)] Removing old rollback... "
    rm -rf ${ROLLBACK}.1
    if [[ $? == 0 ]]; then
        echo -e "\e[92m[DONE]\e[0m"
    else
        echo -e "\e[91m[FAIL]\e[0m"
    fi
  fi

  # Renames logs .1 trough .4
  while [[ $CNT -ne 1 ]] ; do
    if [ -d ${ROLLBACK}.${P_CNT} ] ; then
      mv ${ROLLBACK}.${P_CNT} ${ROLLBACK}.${CNT}
    fi
    let CNT=CNT-1
    let P_CNT=P_CNT-1
  done

  # Renames current log to .1
  mv $ROLLBACK ${ROLLBACK}.1
fi
}

RollbackRotate
printf "[$(hostname -s)] Creating new Rollback directory... "
cp -rp ${CODEDIR} ${ROLLBACK}
if [[ $? == 0 ]]; then
        echo -e "\e[92m[DONE]\e[0m"
else
        echo -e "\e[91m[FAIL]\e[0m"
fi
