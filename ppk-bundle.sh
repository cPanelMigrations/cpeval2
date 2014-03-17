#! /bin/sh

die() {
    echo "$0: $@" 1>&2
    exit 1
}

usage() {
    [ -n "$1" ] && echo "$1" 1>&2
    echo "usage: $0 dir bundle" 1>&2
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

DIR="$1"
BUNDLE="$2"

if [ ! -d "$DIR" ]; then
    die "Could not find directory $DIR"
fi

for subdir in lib scripts; do
    if [ ! -d "$DIR/$subdir" ]; then
        die "Could not find $subdir/ directory in $DIR"
    fi
done

sed 's/^    //' <<'EOF' > "$BUNDLE"
    #! /usr/bin/perl

    use strict;
    use warnings;

    use POSIX        ();
    use File::Temp   ();
    use File::Find   ();
    use MIME::Base64 ();

    sub extract {
        my ($tmpdir) = @_;

        pipe my ($out, $in) or die("Unable to pipe(): $!");
        my $pid = fork();

        if ($pid == 0) {
            close $in;
            POSIX::dup2(fileno($out), fileno(STDIN)) or die("Unable to dup2(): $!");

            chdir($tmpdir) or die("Unable to chdir() to $tmpdir: $!");
            exec qw(tar mpzxf -) or die("Unable to exec(): $!");
        } elsif (!defined($pid)) {
            die("Unable to fork(): $!");
        }

        close $out;

        while (my $len = read(DATA, my $buf, 3445)) {
            my $decoded = MIME::Base64::decode_base64($buf);

            syswrite($in, $decoded) or die("Failed to syswrite(): $!");
        }

        close $in;
        waitpid $pid, 0;
    }

    sub run {
        my ($tmpdir, @args) = @_;
        my $main = "$tmpdir/scripts/main.pl";
        my $lib  = "$tmpdir/lib";

        my $pid = fork();

        if ($pid == 0) {
            $ENV{'PERLLIB'} ||= '.';
            $ENV{'PERLLIB'} = "$lib:$ENV{'PERLLIB'}";
            exec $^X, $main, @args or die("Unable to exec() $main: $!");
        } elsif (!defined($pid)) {
            die("Unable to fork(): $!");
        }

        waitpid($pid, 0);

        return $?;
    }

    sub cleanup {
        my (@dirs) = @_;

        File::Find::finddepth({
            'no_chdir' => 1,
            'wanted'   => sub {
                if ( -d $File::Find::name ) {
                    rmdir $File::Find::name;
                } else {
                    unlink $File::Find::name;
                }
            }
        }, @dirs);
    }

    my $tmpdir = File::Temp::mkdtemp('/tmp/.perl-ppk-XXXXXX') or die("Cannot create temporary directory: $!");

    $SIG{'INT'} = sub {
        cleanup($tmpdir);
    };

    extract($tmpdir);
    run($tmpdir, @ARGV);
    cleanup($tmpdir);

    exit $?;

    __DATA__
EOF

tar -C "$DIR" -pcf - lib scripts | gzip | openssl enc -base64 >> "$BUNDLE"
chmod 0755 "$BUNDLE"
