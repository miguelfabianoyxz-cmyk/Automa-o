package com.itau.massasdns.model;

import java.util.List;

public record MassaData(List<String> headers, List<List<String>> rows) {}
