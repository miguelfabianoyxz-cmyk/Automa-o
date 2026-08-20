package com.itau.massasdns.model;

import java.util.List;

public record ParseResponse(MassaData massas, List<DNSEntry> dns, CombinedData combined) {}
