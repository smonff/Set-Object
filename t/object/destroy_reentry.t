#!/usr/bin/env perl

# A set member whose DESTROY calls back into the set holding it, while
# that set is being destroyed.
#
# Set::Object::DESTROY clears the set's internal pointer before releasing
# the members. Any method called on the set from a member's DESTROY then
# dereferences a NULL pointer, and the process gets a SIGSEGV.
#
# Each case runs in a child process, so a crash does not take the whole
# test file down.

use strict;
use warnings;
use Test::More;
use POSIX ();
use Set::Object;

plan skip_all => 'fork() and signals do not behave the same on Windows'
    if $^O eq 'MSWin32';

{
    package MemberTouchingItsSet;
    use Scalar::Util qw(weaken);

    sub new {
        my ($class, $set, $method) = @_;
        my $self = bless { set => $set, method => $method }, $class;
        weaken $self->{set};
        return $self;
    }

    sub DESTROY {
        my $self   = shift;
        my $method = $self->{method};
        return unless $self->{set};

        # size() and members() take no argument
        my @arguments = $method eq 'size' || $method eq 'members' ? () : ($self);
        $self->{set}->$method(@arguments);
    }
}

for my $method (qw(remove includes insert size members)) {
    my $child_pid = fork;
    die "Cannot fork: $!" unless defined $child_pid;

    if ($child_pid == 0) {
        my $set    = Set::Object->new;
        my $member = MemberTouchingItsSet->new($set, $method);
        $set->insert($member);
        undef $member;

        # The set holds the only strong reference to its member: freeing
        # the set releases the member, which calls back into the set
        undef $set;

        POSIX::_exit(0);    # Skip Test::More's END block in the child
    }

    waitpid $child_pid, 0;
    my $signal = $? & 127;

    is $signal, 0, "calling ->$method on a set from its member's DESTROY does not crash";
}

done_testing;
