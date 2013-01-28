package Easy::Template;

use strict;
use Carp;

our $VERSION = 0.01;

my $obj = {};

sub new {
    my ($class,$file,$enc) = @_;
    !$file and croak "No template file specified\n";
    my $fh;
    $enc ? (open $fh,"<:encoding($enc)",$file) || croak "Can't open $file:$!"
         : (open $fh,"<:utf8",$file) || croak "Can't open $file:$!";
    my $self =  bless \do{my $new},ref $class || $class;
    $self->file($file)->encoding($enc || 'utf8')->FH($fh);
    return $self;
}

sub file {
    my $self = shift;
    return $obj->{$self}{file} if !@_;
    $obj->{$self}{file} = shift;
    return $self;
}

sub encoding {
    my $self = shift;
    return $obj->{$self}{encoding} if !@_;
    $obj->{$self}{encoding} = shift;
    return $self;
}

sub FH {
    my $self = shift;
    return $obj->{$self}{FH} if !@_;
    $obj->{$self}{FH} = shift;
    return $self;
}

sub param {
    my ($self,%arg) = @_;
    for my $key (keys %arg){
        croak "Duplicate parameter '$key'" if exists $obj->{$self}{param}{$key};
        $obj->{$self}{param}{$key} = $arg{$key};
    }
    return $self;
}

sub if {
    my ($self,@if_names) = @_;
    for my $name(@if_names){
        croak "if name '$name' is already set" if exists $obj->{$self}{if}{$name};
        $obj->{$self}{if}{$name} = 1;
    }
    return $self;
}

sub output {
    my $self = shift;
    my $fh = $self->FH;
    LINE:
    while (<$fh>){
        
        # case code
        if (/^&/){
            my $code_begin = $.;
            (my $code = $_) =~ s/^&\s*//;
            while(<$fh>){
                
                # end of code
                if (s/^&\s*//){
                    my ($left,$right) = split/=/;
                    
                    # return as list context
                    if($left =~ /[(]/){
                        my @var_names;
                        while($left =~ /\$([a-zA-Z_][a-zA-Z0-9_]*)/g){
                            my $var_name = $1;
                            croak "parameter [$var_name] already exists '".$self->file."' $. line" if exists $obj->{$self}{param}{$var_name};
                            push @var_names,"\$obj->{'$self'}{param}{$var_name}";
                        }
                        $code .= "(@{ [ join(',',@var_names) ] }) = $right";
                        eval "$code";
                        if($@){
                            chomp $@;
                            croak "error during evaluating code:$@ at '".$self->file."' $. line ";
                        }
                    }
                    # return as scalar context
                    else{
                        my ($var_name) = $left =~ /\$([a-zA-Z_][a-zA-Z0-9_]*)/;
                        my $res;
                        $code .= '$res = '.$right;
                        eval "$code";
                        if($@){
                            chomp $@;
                            croak "error during evaluating code:$@ at '".$self->file."' $. line ";
                        }
                        croak "parameter [$var_name] already exists at '".$self->file."' $. line" if exists $obj->{$self}{param}{$var_name};
                        $obj->{$self}{param}{$var_name} .= $res;
                    }
                    next LINE;
                }
                croak "Can't find code terminater '&' anywhere at '".$self->file."' $code_begin line" if eof;
                $code .= $_;
            }
        }
        
        # case replace value
        $self->replace(\$_) if /(?:^|[^\\])\$[a-zA-Z_][a-zA-Z0-9_]*/;
        
        # case if divergence
        if (/<if\s*name\s*=\s*["']?[a-zA-Z_][a-zA-Z0-9_]*["']?\s*>/i){
            # case only a line
            if (m{<if\s*name\s*=\s*["']?[a-zA-Z_][a-zA-Z0-9_]*["']?\s*>.+?</if>}i){
                s{<if\s*name\s*=\s*["']?([a-zA-Z_][a-zA-Z0-9_]*)["']?\s*>(.+?)</if>}{$self->select_divergence($1,$2)}ie;
            }
            # case multi lines
            else{
                my $code_begin = $.;
                my ($if_before,$if_name,$if_all) = /^(.*?)<if\s*name\s*=\s*["']?([a-zA-Z_][a-zA-Z0-9_]*)["']?\s*>(.*)/is;
                while (<$fh>){
                    $self->replace(\$_) if /(?:^|[^\\])\$[a-zA-Z_][a-zA-Z0-9_]*/;
                    last if m{</if>}i;
                    croak "Can't find if terminater '</if>' any where in ".$self->file." $code_begin line " if eof;
                    $if_all .= $_;
                }
                s{^(.*?)</if>(.*)}{$if_before.$self->select_divergence($if_name,$if_all.$1,$code_begin).$2}ies;
            }
        }
        
        s/\\\$/\$/g;
        s/^\\&/&/;
        $obj->{$self}{output} .= $_;
    };
    my @no_exists = grep {!exists $obj->{$self}{match}{$_}}keys %{$obj->{$self}{param}};
    croak qq<Can't find [@{ [ join(',',map{"\$$_"}@no_exists) ] }] in template '>.$self->file."'" if @no_exists;
    return $obj->{$self}{output};
}

sub replace {
    my ($self,$ref) = @_;
    MATCH:
    while($$ref =~ /(?:^|[^\\])\$([a-zA-Z_][a-zA-Z0-9_]*)/g){
        my $mask = $1 || croak 'Unescaped character "$" in "'.$self->file."\" line $. ";
        for my $key(keys %{$obj->{$self}{param}}){
            if ($mask =~ /^$key/){
                $$ref =~ s/\$$key/$obj->{$self}{param}{$key}/;
                $obj->{$self}{match}{$key}++;
                next MATCH;
            }
        }
        croak "Can't find parameter [$mask] anywhere in $0\nor you missed escaping [\$$mask] in ".$self->file." called";
    }
}
sub select_divergence {
    my ($self,$if_name,$if_all,$code_begin) = @_;
    $code_begin ||= $.;
    croak "Can't find if terminater '</if>' any where in ".$self->file." $code_begin line " if $if_all =~ /<if\s*name\s*=\s*["']?[a-zA-Z_][a-zA-Z0-9_]*["']?\s*>/i;
    if ($if_all =~ /^(.+?)<else>(.+)/ims){
        return $obj->{$self}{if}{$if_name} ? $1 : $2;
    }
    else{
        return $obj->{$self}{if}{$if_name} ? $if_all : q{};
    }
}

1;

__END__

=pod

=head1 NAME Easy::Template

 a very simple template module

=head1 SYNOPSYS
 
 use Easy::Template
 
 my $temp = Easy::Template->new('/path/to/template.html','shift-jis');
 
 # set param and print
 print $temp->param(hello => 'world')->output;
 
 # set if divergence and print
 print $temp->if(qw/foo bar/)->output;

=head1 METHOD

 $temp->param(name => 'val') set parameter with hash

 $temp->if(qw/foo bar/)      set if divergence whith list (possible whith an scalar)

 $temp->output               returns parsed content

=head1 TEMPLATE FILE EXAMPLE
 
 <body>
 <h1>Hello World</h1>
 <p>hello $world</p>
 <if name='foo'>foo</if>
 <if name='bar'>bar<else>baz</if>
 & my $now = time;
 my $ONE_HOUR = 3600;
 & my $after_an_hour = $time + $ONE_HOUR;
 <p>after an hour is $after_an_our</p>
 <body>

 <!---
   $wold        If you want to replace value,specify the '$' prefix just before param name.
   
   \$world      If you want to write '$' as it is,you must escape it to '\$'.

   <if name='foo'>Foo<else>Bar</if>
                If $temp->if('foo') is true, it returns 'Foo'. Else 'Bar'.

   <if name='baz'>Baz</if>
                If $temp->if('baz') is true, it returns 'Baz'. Else ''
   
   &            The next follow strings evaluate as perl script till next '&' appears alone at line head.
 --->

=head1 AUTHOR

 Tooru IWASAKI  2013/01/27

=cut
