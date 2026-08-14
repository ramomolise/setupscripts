# HestiaCP / OCI clean recovery checklist

Use this when the safest recovery is a clean operating-system volume rather
than repairing an unknown or compromised control-panel installation in place.

## Before replacement

1. Create and verify a boot-volume backup or snapshot.
2. Export every required WordPress or application database.
3. Back up `/home` content, web roots, certificates, and custom configuration.
4. Export required mailboxes before replacing a mail server.
5. Record DNS, firewall, reverse-DNS, DKIM, SPF, and DMARC state without storing
   secrets in this repository.
6. Confirm that another administrator can access the cloud account.

## Recovery sequence

1. Provision a clean supported Debian or Ubuntu image.
2. Attach it to the existing instance only after the old boot volume is safely
   detached or snapshotted.
3. Boot and verify SSH access before deleting anything old.
4. Install HestiaCP on the fresh OS using
   `scripts/debian/hestia-install.sh`.
5. Restore one service at a time: DNS, web, database, mail, then scheduled jobs.
6. Validate TLS, backups, outbound mail reputation, and monitoring.
7. Keep the old volume until the restored system has passed a full acceptance
   test and at least one new backup has been restored successfully.

Never place exported databases, mail, credentials, cloud identifiers, or public
server addresses in Git.
