Name:           perl-Lim-Plugin-Orr
Version:        0.10
Release:        1%{?dist}
Summary:        Lim::Plugin::Orr - ...

Group:          Development/Libraries
License:        GPL+ or Artistic
URL:            https://github.com/jelu/lim-plugin-orr/
Source0:        lim-plugin-orr-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildArch:      noarch
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl(Test::Simple)
BuildRequires:  perl(Lim) >= 0.16

Requires:  perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:  perl(Lim) >= 0.16

%description
This plugin lets you manage a Orr installation via Lim.

%package -n perl-Lim-Plugin-Orr-Common
Summary: Common perl libraries for Orr Lim plugin
Group: Development/Libraries
Version: 0.10
%description -n perl-Lim-Plugin-Orr-Common
Common perl libraries for Orr Lim plugin.

%package -n perl-Lim-Plugin-Orr-Server
Summary: Server perl libraries for Orr Lim plugin
Group: Development/Libraries
Version: 0.10
%description -n perl-Lim-Plugin-Orr-Server
Server perl libraries for Orr Lim plugin.

%package -n perl-Lim-Plugin-Orr-Client
Summary: Client perl libraries for Orr Lim plugin
Group: Development/Libraries
Version: 0.10
%description -n perl-Lim-Plugin-Orr-Client
Client perl libraries for communicating with the Orr Lim plugin.

%package -n perl-Lim-Plugin-Orr-CLI
Summary: CLI perl libraries for Orr Lim plugin
Group: Development/Libraries
Version: 0.10
%description -n perl-Lim-Plugin-Orr-CLI
CLI perl libraries for controlling a local or remote Orr installation
via Orr Lim plugin.

%package -n lim-management-console-orr
Requires: lim-management-console-common >= 0.16
Summary: Orr Lim plugin Management Console files
Group: Development/Libraries
Version: 0.10
%description -n lim-management-console-orr
Orr Lim plugin Management Console files.


%prep
%setup -q -n lim-plugin-orr


%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT
make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
mkdir -p %{buildroot}%{_datadir}/lim/html
mkdir -p %{buildroot}%{_datadir}/lim/html/_orr
mkdir -p %{buildroot}%{_datadir}/lim/html/_orr/js
install -m 644 %{_builddir}/lim-plugin-orr/html/_orr/about.html %{buildroot}%{_datadir}/lim/html/_orr/about.html
install -m 644 %{_builddir}/lim-plugin-orr/html/_orr/index.html %{buildroot}%{_datadir}/lim/html/_orr/index.html
install -m 644 %{_builddir}/lim-plugin-orr/html/_orr/js/application.js %{buildroot}%{_datadir}/lim/html/_orr/js/application.js


%check
make test


%clean
rm -rf $RPM_BUILD_ROOT


%files -n perl-Lim-Plugin-Orr-Common
%defattr(-,root,root,-)
%{_mandir}/man3/Lim::Plugin::Orr.3*
%{perl_vendorlib}/Lim/Plugin/Orr.pm

%files -n perl-Lim-Plugin-Orr-Server
%defattr(-,root,root,-)
%{_mandir}/man3/Lim::Plugin::Orr::Server.3*
%{perl_vendorlib}/Lim/Plugin/Orr/Server.pm

%files -n perl-Lim-Plugin-Orr-Client
%defattr(-,root,root,-)
%{_mandir}/man3/Lim::Plugin::Orr::Client.3*
%{perl_vendorlib}/Lim/Plugin/Orr/Client.pm

%files -n perl-Lim-Plugin-Orr-CLI
%defattr(-,root,root,-)
%{_mandir}/man3/Lim::Plugin::Orr::CLI.3*
%{perl_vendorlib}/Lim/Plugin/Orr/CLI.pm

%files -n lim-management-console-orr
%defattr(-,root,root,-)
%{_datadir}/lim/html/_orr/about.html
%{_datadir}/lim/html/_orr/index.html
%{_datadir}/lim/html/_orr/js/application.js


%changelog
* Thu Aug 13 2013 Jerry Lundström < lundstrom.jerry at gmail.com > - 0.10-1
- Initial package for Fedora

