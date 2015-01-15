package MT::Plugin::TwoFactorAuthGoogle;
use strict;
use warnings;
use base qw( MT::Plugin );
use vars qw( $MYNAME $VERSION $SCHEMA_VERSION );

use MT::TwoFactorAuthGoogle::Settings;

use Auth::GoogleAuthenticator;
use MIME::Base64;

$MYNAME = 'TwoFactorAuthGoogle';
$VERSION = '0.1';
$SCHEMA_VERSION = '0.02';

my $plugin = __PACKAGE__->new({
    'name' => $MYNAME,
    'id' => lc $MYNAME,
    'key' => lc $MYNAME,
    'version' => $VERSION,
    'author_name' => '<__trans phrase="SKYARC System Co.,Ltd.">',
    'author_link' => 'http://www.skyarc.co.jp/',
    'description' => '<__trans phrase="Add two-factor authentication to your Movable Type.">',
    'doc_link' => 'http://www.skyarc.co.jp/',
    'l10n_class' => $MYNAME.'::L10N',
    'settings' => new MT::PluginSettings([
        ["enable_two_factor_auth", {"default" => "", "scope" => "system"}]
    ]),
    'schema_version' => $SCHEMA_VERSION,
    'registry' => {
        'object_types' => {
            'TwoFactorAuthGoogle' => 'MT::TwoFactorAuthGoogle::Settings'
        },
        'callbacks' => {
            "MT::App::CMS::template_source.login_mt" => \&_tmpl_source_login,
            "MT::App::CMS::template_source.edit_author" => \&_tmpl_src_edit_author,
            "MT::App::CMS::post_signin.app" => \&_post_signin,
            "cms_post_save" => \&_post_save,
        }
    }
});
MT->add_plugin($plugin);

sub _is_type_author { return shift->param("_type") eq "author"; }
sub _is_mode_save { return shift->param("__mode") eq "save"; }

sub _post_save {
    my ($cb, $app, $author) = @_;
    return if (not _is_type_author($app) or not _is_mode_save($app));
    my $model = MT::TwoFactorAuthGoogle::Settings->load({author_id => $app->param("id")});
    $model = MT::TwoFactorAuthGoogle::Settings->new() if (not $model);
    $model->author_id($app->param("id"));
    if (not $model->enable_twofactorauth()) {
        $model->secret(_genRandom(8));
    }
    $model->enable_twofactorauth(($app->param("enable_twofactorauth") eq "true" ? 1: 0));
    $model->save() or die($model->errstr);
}

sub _genRandom {
    my $size = shift;
    my $random;
    my @string = ("a".."z","A".."Z",0..9);
    $random .= $string[int(rand(scalar(@string)))] for (0 .. $size);
    return $random;
}

sub _tmpl_src_edit_author {
    my ($cb, $app, $tmpl) = @_;
    my $author = MT::Author->load({"id" => $app->param("id")});
    my $model = MT::TwoFactorAuthGoogle::Settings->load({author_id => $app->param("id")});
    my ($enable_twofactorauth, $auth, $qrcode);
    if ($model and $model->enable_twofactorauth() == 1) {
        $enable_twofactorauth = q| checked="checked"|;
        $auth = Auth::GoogleAuthenticator->new(secret => $model->secret());
        $qrcode = $auth->registration_qr_code($ENV{"SERVER_NAME"}."::MT::".$author->name);
        $qrcode = encode_base64($qrcode);
    }

    my $plugin = $app->component("TwoFactorAuthGoogle");
    my $old = quotemeta(<<'HTML');
      <mtapp:setting
         id="pass_verify"
         label="<__trans phrase="Confirm Password">"
         required="$password_required"
         hint="<__trans phrase="Repeat the password for confirmation.">">
        <input type="password" name="pass_verify" id="pass_verify" class="text password" value="" />
      </mtapp:setting>

      <mt:unless name="new_object">
        <mt:if name="hint">
      <mtapp:setting
         id="hint"
         required="0"
         label="<__trans phrase="Password recovery word/phrase">"
         hint="<__trans phrase="This word or phrase is not used in the password recovery.">">
        <input name="hint" id="hint" value="<mt:var name="hint" escape="html">" />
      </mtapp:setting>
        </mt:if>
      </mt:unless>
    </div>
HTML
    my $new = $plugin->translate_templatized(<<HTML);
<mtapp:setting id="twoFactorAuth" label="<__trans phrase="Enable Two factor auth.">">
    <input type="checkbox" value="true" name="enable_twofactorauth" id="enable_twofactorauth"${enable_twofactorauth} />
</mtapp:setting>
HTML
    if ($qrcode) {
        $new .= $plugin->translate_templatized(<<HTML);
<div id="twoFactorAuth_initialize">
<mtapp:setting id="twoFactorAuth_qrcode" label="<__trans phrase="Read the QRcode by GoogleAuthenticator in your smartphone.">">
    <img src="data:image/png;base64,${qrcode}" />
</mtapp:setting>
</div>
HTML
    $new .= <<'HTML';
<script type="text/javascript">
jQuery(function ($) {
    $("#twoFactorAuth_initialize").hide();
    if ($("#enable_twofactorauth").prop("checked")) $("#twoFactorAuth_initialize").show();
    $("#enable_twofactorauth").on("click", function () {
        $("#twoFactorAuth_initialize").toggle();
    });
});
</script>
HTML
    }
    $$tmpl =~ s/$old/$&$new/msxi;
}

sub _tmpl_source_login {
    my ($cb, $app, $tmpl) = @_;
    my $plugin = $app->component("TwoFactorAuthGoogle");
    my $config = {};
    $plugin->load_config($config, 'system');
    return if (not $config->{"enable_two_factor_auth"});

    my $add = $plugin->translate_templatized(<<'HTML');
<mtapp:setting
    id="otp_"
    label="<__trans phrase="otp">"
    label_class="top-label">
    <input type="text" name="otp" id="otp" class="text full" />
</mtapp:setting>
HTML
    $$tmpl =~ s/<div\s+[^>]*>/${add}${&}/msxi;
}

sub _post_signin {
    my ($cb, $app, $res, $ctx) = @_;
    my $plugin = $app->component('TwoFactorAuthGoogle');

    ## @MEMO: ID/PASSWORDでの新規ログイン時以外は処理しない
    return if ($res != MT::Auth::NEW_LOGIN());
    my $model = MT::TwoFactorAuthGoogle::Settings->load({author_id => $app->user->id});
    return if (not $model or not $model->enable_twofactorauth());
    
    my $auth = Auth::GoogleAuthenticator->new(secret => $model->secret());
    return if ($auth->totp() eq $app->param("otp"));
    $app->logout();
}

