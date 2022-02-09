# Copyright 2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DOCS_BUILDER="doxygen"
inherit cmake docs

DESCRIPTION="Cross-platform library for building Telegram clients"
HOMEPAGE="https://core.telegram.org/tdlib https://github.com/tdlib/td"
SRC_URI="https://github.com/tdlib/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Boost-1.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="benchmark dotnet java +jumbo-build static-libs test"

RESTRICT="!test? ( test )"

DEPEND="
	dev-libs/openssl:=
	sys-libs/zlib:=
	dotnet? ( virtual/dotnet-sdk:* )
	java? ( virtual/jdk:*[-headless-awt] )
"
RDEPEND="${DEPEND}"
BDEPEND="
	dev-lang/php[cli]
	dev-util/gperf
"

DOCS=( CHANGELOG.md README.md )

TEST_TARGETS=(
	test-crypto
	#test-online -- requires network
	#test-tdutils -- hangs
	#run_all_tests -- segfaults
)
BENCH_TARGETS=(
	bench_{actor,empty,handshake,misc}
	bench_http
	check_tls
	#bench_{db,tddb} -- fail
	#bench_http_server{,_cheat,_fast} - hang
	#bench_http_reader -- fails
	#check_proxy -- requires proxy
	#rmdir -- fails
	#wget -- requires network
)

src_prepare() {
	sed "/find_program(CCACHE_FOUND ccache)/d" -i CMakeLists.txt || die
	echo "" > gen_git_commit_h.sh || die

	use test || cmake_comment_add_subdirectory test
	use benchmark || cmake_comment_add_subdirectory benchmark

	cmake_src_prepare
}

src_configure() {
	local mycmakeargs=(
		-DTD_ENABLE_DOTNET=$(usex dotnet)
	)

	if use java; then
		local JAVA_HOME=$(java-config -O)
		local JAVA_AWT_LIBRARY=$(echo "${JAVA_HOME}"/jre/lib/*/libjawt.so)
		local JAVA_JVM_LIBRARY=$(echo "${JAVA_HOME}"/jre/lib/*/libjava.so)

		mycmakeargs+=(
			-DTD_ENABLE_JNI=ON
			-DJAVA_AWT_LIBRARY="${JAVA_AWT_LIBRARY}"
			-DJAVA_JVM_LIBRARY="${JAVA_JVM_LIBRARY}"
			-DJAVA_INCLUDE_PATH="${JAVA_HOME}/include"
			-DJAVA_INCLUDE_PATH2="${JAVA_HOME}/include/linux"
			-DJAVA_AWT_INCLUDE_PATH="${JAVA_HOME}/include"
		)
	fi

	cmake_src_configure
}

src_compile() {
	einfo "Generating TL source file"
	cmake_build tl_generate_common tl_generate_json

	einfo "Generating git_info.h"
	cat <<- EOF > auto/git_info.h || die
	#pragma once
	#define GIT_COMMIT "v${PV}"
	#define GIT_DIRTY 0
	EOF

	if ! use jumbo-build; then
		einfo "Splitting source files"
		php SplitSource.php || die
	fi

	# Let's build the library
	einfo "Building TDLib"
	cmake_src_compile

	if use test; then
		einfo "Building tests"
		cmake_build "${TEST_TARGETS[@]}"
	fi

	if use doc; then
		einfo "Generating docs"
		docs_compile
	fi
}

src_test() {
	# segfault
	#cmake_src_test

	pushd "${BUILD_DIR}"/test > /dev/null || die
	for exe in "${TEST_TARGETS[@]}"; do
		einfo "Running ${exe}"
		./"${exe}" || die "${exe} failed"
	done
	popd > /dev/null || die

	if use benchmark; then
		pushd "${BUILD_DIR}"/benchmark > /dev/null || die
		for exe in "${BENCH_TARGETS[@]}"; do
			einfo "Running ${exe}"
			./"${exe}" || die "${exe} failed"
		done
		popd > /dev/null || die
	fi
}

src_install() {
	cmake_src_install

	docompress -x /usr/share/doc/${PF}/example
	dodoc -r example

	if ! use static-libs; then
		einfo "Removing static libraries"
		find "${D}" -type f -name '*.a' -delete || die
	fi
}