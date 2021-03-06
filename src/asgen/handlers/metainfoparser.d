/*
 * Copyright (C) 2016-2018 Matthias Klumpp <matthias@tenstral.net>
 *
 * Licensed under the GNU Lesser General Public License Version 3
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the license, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this software.  If not, see <http://www.gnu.org/licenses/>.
 */

module asgen.handlers.metainfoparser;

import std.path : baseName;
import std.uni : toLower;
import std.string : format;
import std.array : empty;
import std.stdio;
import appstream.Metadata;
import appstream.Component;

import asgen.result;
import asgen.utils;


private bool isAcceptableMetainfoLicense (string licenseExpression) pure
{
    import asgen.bindings.appstream_utils;

    bool requiresAllTokens = true;
    uint licenseGoodCnt = 0;
    uint licenseBadCnt = 0;

	auto tokens = spdxLicenseTokenize (licenseExpression);
	if (tokens.length == 0)
		return false;

	// we don't consider very complex expressions valid
    foreach (const ref t; tokens) {
        if (t == "(" || t == ")")
            return false;
    }

	// this is a simple expression parser and can be easily tricked
    foreach (const ref t; tokens) {
        if (t == "+")
            continue;
        if (t == "|") {
            requiresAllTokens = false;
            continue;
        }
        if (t == "&") {
            requiresAllTokens = true;
            continue;
        }

        if (spdxLicenseIsMetadataLicense (t))
            licenseGoodCnt++;
        else
            licenseBadCnt++;
    }

	// any valid token makes this valid
	if (!requiresAllTokens && licenseGoodCnt > 0)
		return true;

	// all tokens are required to be valid
	if (requiresAllTokens && licenseBadCnt == 0)
		return true;

	// this license or license expression was bad
    return false;
}

Component parseMetaInfoFile (Metadata mdata, GeneratorResult gres, const string data, const string mfname)
{
    try {
        mdata.parse (data, FormatKind.XML);
    } catch (Exception e) {
        gres.addHint ("general", "metainfo-parsing-error", e.msg);
        return null;
    }

    auto cpt = mdata.getComponent ();
    if (cpt is null)
        return null;

    // check if we have a component-id, a component without ID is invalid
    if (cpt.getId.empty) {
        gres.addHint (null, "metainfo-no-id", ["fname": mfname]);
        return null;
    }
    gres.addComponent (cpt);

    // check if we can actually legally use this metadata
    if (!isAcceptableMetainfoLicense (cpt.getMetadataLicense())) {
        gres.addHint (cpt, "metainfo-license-invalid", ["license": cpt.getMetadataLicense()]);
        return null;
    }

    // quit immediately if we have an unknown component type
    if (cpt.getKind () == ComponentKind.UNKNOWN) {
        gres.addHint (cpt, "metainfo-unknown-type");
        return null;
    }

    return cpt;
}

Component parseMetaInfoFile (GeneratorResult gres, const string data, const string mfname)
{
    auto mdata = new Metadata ();
    mdata.setLocale ("ALL");
    mdata.setFormatStyle (FormatStyle.METAINFO);

    return parseMetaInfoFile (mdata, gres, data, mfname);
}

unittest {
    import std.stdio : writeln;
    writeln ("TEST: ", "Metainfo Parser");

    assert (isAcceptableMetainfoLicense ("FSFAP"));
    assert (isAcceptableMetainfoLicense ("CC0"));
    assert (isAcceptableMetainfoLicense ("CC0-1.0"));
    assert (isAcceptableMetainfoLicense ("0BSD"));
    assert (isAcceptableMetainfoLicense ("MIT AND FSFAP"));
    assert (!isAcceptableMetainfoLicense ("GPL-2.0 AND FSFAP"));
    assert (isAcceptableMetainfoLicense ("GPL-3.0+ or GFDL-1.3-only"));
    assert (!isAcceptableMetainfoLicense ("GPL-3.0+ and GFDL-1.3-only"));
}
